function [mpc, applied] = apply_transmission_constraints(mpc, data, hour, config)
%APPLY_TRANSMISSION_CONSTRAINTS Build physical and market transmission limits.
% RATE_A is a symmetric AC apparent-power limit (MVA). Excel FlowMin/FlowMax
% are directional market-flow limits. By default they are treated as MW and
% formulated with MATPOWER's DC-linear flow equations, never copied to RATE_A.
if nargin < 4, config = struct(); end
limitType = upper(string(config_value(config, 'branchLimitType', 'MW')));
if ~any(limitType == ["MVA", "MW", "CURRENT"])
    error('case1354:InvalidBranchLimitType', ...
        'branchLimitType must be MVA, MW, or CURRENT.');
end
if limitType == "CURRENT"
    error('case1354:UnsupportedCurrentLimit', ...
        'CURRENT limits require line current units and voltage-base conversion; the workbook does not provide them.');
end

t = data.TransmissionConstr;
if isempty(t), applied = empty_applied(); return; end
if ismember('Hour', t.Properties.VariableNames)
    t = t(number_column(t, 'Hour', nan) == hour, :);
end
specRows = cell(0, 9); termRows = cell(0, 5); appliedRows = cell(0, 16);
for i = 1:height(t)
    id = strtrim(string(t.('TransmissionID(Branch,BranchGroup,Nomogram)')(i)));
    typ = strtrim(string(t.('Type')(i)));
    flowMin = number_column(t, 'FlowMin', nan); flowMax = number_column(t, 'FlowMax', nan);
    lo = flowMin(i); hi = flowMax(i);
    [terms, message] = resolve_terms(id, typ, data, mpc);
    matched = ~isempty(terms) && isfinite(lo) && isfinite(hi) && lo <= hi;
    original = nan; finalRate = nan; source = "NotApplied"; enforcement = "NotApplied";
    directBranch = height(terms) == 1 && terms.TermType(1) == "Branch" && abs(terms.Coefficient(1)-1) < 1e-12;
    if matched && limitType == "MVA" && directBranch && abs(abs(lo) - abs(hi)) < 1e-9
        idx = terms.ElementIndex(1); original = mpc.branch(idx, 6);
        marketRate = max(abs([lo hi]));
        if original > 0, finalRate = min(original, marketRate); source = ternary(finalRate < original, "BothMin", "OriginalRateA");
        else, finalRate = marketRate; source = "MarketMVA"; end
        mpc.branch(idx, 6) = finalRate;
        enforcement = "AC_RATE_A_MVA";
        message = "Symmetric MVA limit applied as min(OriginalRateA, MarketLimit).";
    elseif matched && limitType == "MW"
        specRows(end+1, :) = {id, typ, lo, hi, "MW", "DC_LINEAR_IN_AC", message, true, hour}; %#ok<AGROW>
        constraintRow = size(specRows, 1);
        for j = 1:height(terms)
            termRows(end+1, :) = {constraintRow, terms.TermType(j), terms.ElementIndex(j), terms.Coefficient(j), terms.ElementName(j)}; %#ok<AGROW>
        end
        enforcement = "DC_LINEAR_FLOW"; source = "MarketMW";
    elseif matched && limitType == "MVA"
        message = "Directional or composite MVA limit cannot be represented by RATE_A; no implicit MW conversion was made.";
        enforcement = "NotApplied"; source = "UnsupportedMVAExpression";
    elseif ~matched
        message = message + " FlowMin/FlowMax invalid or no term resolved.";
    end
    branchIndex = nan;
    if directBranch
        branchIndex = terms.ElementIndex(1);
        if isnan(original), original = mpc.branch(branchIndex, 6); end
    end
    appliedRows(end+1, :) = {hour, id, typ, limitType, lo, hi, original, finalRate, branchIndex, ...
        matched, enforcement, source, "", message, false, false}; %#ok<AGROW>
end

applied = cell2table(appliedRows, 'VariableNames', applied_names());
if ~isempty(specRows)
    mpc.marketFlowConstraints = cell2table(specRows, 'VariableNames', ...
        {'TransmissionID','Type','FlowMinMW','FlowMaxMW','Unit','ConstraintModel','Message','Resolved','Hour'});
    mpc.marketFlowTerms = cell2table(termRows, 'VariableNames', ...
        {'ConstraintRow','TermType','ElementIndex','Coefficient','ElementName'});
    mpc = apply_market_flow_constraint_callbacks(mpc);
end
end

function [terms, message] = resolve_terms(id, typ, data, mpc)
terms = empty_terms(); message = ""; kind = lower(strtrim(typ));
if contains(kind, 'branch')
    [idx, name] = branch_index(id, data, mpc);
    if isempty(idx), message = "BranchName exact match failed."; return; end
    terms = add_term(terms, "Branch", idx, 1, name); return;
elseif kind == "bg" || contains(kind, 'branchgroup')
    g = data.BranchGroup; mask = normalize_id(string(g.('BranchGroupName'))) == normalize_id(id);
    for j = find(mask).'
        [idx, name] = branch_index(string(g.('BranchName')(j)), data, mpc);
        if isempty(idx), message = message + " Unmatched group branch: " + string(g.('BranchName')(j)) + "."; continue; end
        coef = numeric_value(g{j, 'Coefficient'}); terms = add_term(terms, "Branch", idx, coef, name);
    end
elseif kind == "ng" || contains(kind, 'nomogram')
    n = data.Nomogram;
    mask = normalize_id(string(n.('NomogramName'))) == normalize_id(id);
    for j = find(mask).'
        vtype = lower(strtrim(string(n.('VariableType(Branch, Generator, Load)')(j))));
        variable = string(n.('VariableID(Branch, Generator, Load)')(j)); coef = numeric_value(n{j, 'Coefficient'});
        if vtype == "branch"
            [idx, name] = branch_index(variable, data, mpc);
            if isempty(idx), message = message + " Unmatched nomogram branch: " + variable + "."; else, terms = add_term(terms, "Branch", idx, coef, name); end
        elseif vtype == "generator"
            [idx, name] = generator_index(variable, data);
            if isempty(idx), message = message + " Unmatched nomogram generator: " + variable + "."; else, terms = add_term(terms, "Generator", idx, coef, name); end
        else
            message = message + " Unsupported nomogram variable type: " + vtype + ".";
        end
    end
else
    message = "Unknown TransmissionConstr Type: " + typ + ".";
end
if isempty(terms), return; end
if strlength(message) == 0, message = "All expression terms resolved by normalized permanent source rows."; end
end

function [idx, name] = branch_index(id, data, mpc)
idx = []; name = ""; names = strtrim(string(data.Branch.('BranchName')));
match = find(strcmpi(names, strtrim(id)), 1);
if ~isempty(match), idx = match; name = names(match); return; end
tokens = regexp(char(id), '\\d+', 'match');
if numel(tokens) >= 2
    f = str2double(tokens{1}); to = str2double(tokens{2});
    idx = find((mpc.branch(:,1)==f & mpc.branch(:,2)==to) | (mpc.branch(:,1)==to & mpc.branch(:,2)==f), 1);
    if ~isempty(idx), name = "Bus" + f + "-" + to; end
end
end

function [idx, name] = generator_index(id, data)
idx = []; name = ""; names = case1354_generator_names(data.Generator, data.Initial);
match = find(normalize_generator_names(names) == normalize_generator_names(id), 1);
if ~isempty(match), idx = match; name = names(match); end
end

function terms = empty_terms()
terms = table(strings(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
    'VariableNames', {'TermType','ElementIndex','Coefficient','ElementName'});
end
function terms = add_term(terms, typ, idx, coef, name)
if isfinite(idx) && isfinite(coef), terms = [terms; {string(typ), double(idx), double(coef), string(name)}]; end
end
function id = normalize_id(id), id = lower(regexprep(strtrim(string(id)), '[^a-zA-Z0-9]', '')); end
function v = number_column(t, name, defaultValue)
if ~ismember(name, t.Properties.VariableNames), v = defaultValue * ones(height(t),1); else, v = t.(name); if ~isnumeric(v), v = str2double(string(v)); end; v = double(v); end
end
function v = numeric_value(x), if isnumeric(x), v = double(x); else, v = str2double(string(x)); end, end
function v = config_value(c, name, defaultValue), if isfield(c,name), v=c.(name); else, v=defaultValue; end, end
function v = ternary(cond,a,b), if cond, v=string(a); else, v=string(b); end, end
function t = empty_applied(), t = cell2table(cell(0,numel(applied_names())), 'VariableNames', applied_names()); end
function names = applied_names()
names = {'Hour','TransmissionID','Type','LimitUnit','FlowMin','FlowMax','OriginalRateA','FinalAppliedRateA','BranchIndex','Matched','EnforcementModel','LimitSource','ConstraintModel','Message','LowerLimitBinding','UpperLimitBinding'};
end
