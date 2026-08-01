function t = build_market_transmission_results(applied, opf, hour)
%BUILD_MARKET_TRANSMISSION_RESULTS Report actual expression, limits and prices.
% Values are MW for the DC-linear market constraint. AC OPF retains the
% standard MVA branch result separately in the Branch sheet.
if isempty(applied), t = empty_results(); return; end
n = height(applied); modelFlow = nan(n,1); acFlow = nan(n,1); muLower = nan(n,1); muUpper = nan(n,1);
valid = isfield(opf,'success') && logical(opf.success);
if valid && isfield(opf,'marketFlow')
    c = opf.marketFlow.constraint;
    for k = 1:n
        idx = find(string(c.TransmissionID) == string(applied.TransmissionID(k)), 1);
        if isempty(idx), continue; end
        modelFlow(k) = dc_expression_value(opf, opf.marketFlow.terms, idx);
        acFlow(k) = ac_expression_value(opf, opf.marketFlow.terms, idx);
        muLower(k) = opf.marketFlow.muLower(idx);
        muUpper(k) = opf.marketFlow.muUpper(idx);
    end
end
lowerBinding = valid & abs(modelFlow - applied.FlowMin) <= 1e-4;
upperBinding = valid & abs(modelFlow - applied.FlowMax) <= 1e-4;
modelViolation = valid & (modelFlow < applied.FlowMin - 1e-4 | modelFlow > applied.FlowMax + 1e-4);
acDeviation = valid & (acFlow < applied.FlowMin - 1e-4 | acFlow > applied.FlowMax + 1e-4);
t = table(repmat(hour,n,1), applied.TransmissionID, applied.Type, applied.LimitUnit, ...
    applied.FlowMin, modelFlow, acFlow, applied.FlowMax, lowerBinding, upperBinding, modelViolation, acDeviation, muLower, muUpper, ...
    applied.EnforcementModel, applied.LimitSource, ...
    'VariableNames', {'Hour','TransmissionID','Type','LimitUnit','FlowMin','ModelFlowMW','ACExpressionMW','FlowMax', ...
    'AtLowerLimit','AtUpperLimit','ModelConstraintViolated','ACExpressionOutsideMWBand','MuLower','MuUpper','EnforcementModel','LimitSource'});
end

function value = ac_expression_value(opf, terms, row)
value = 0; rows = terms.ConstraintRow == row;
for j = find(rows).'
    coef = terms.Coefficient(j); idx = terms.ElementIndex(j);
    if terms.TermType(j) == "Branch", value = value + coef * opf.branch(idx,14);
    elseif terms.TermType(j) == "Generator", value = value + coef * opf.gen(idx,2);
    elseif terms.TermType(j) == "Constant", value = value + coef;
    end
end
end
function value = dc_expression_value(opf, terms, row)
[~, Bf, ~, Pfinj] = makeBdc(opf.baseMVA, opf.bus, opf.branch);
va = opf.bus(:,9) * pi / 180; value = 0; rows = terms.ConstraintRow == row;
for j = find(rows).'
    coef = terms.Coefficient(j); idx = terms.ElementIndex(j);
    if terms.TermType(j) == "Branch", value = value + coef * opf.baseMVA * (Bf(idx,:) * va + Pfinj(idx));
    elseif terms.TermType(j) == "Generator", value = value + coef * opf.gen(idx,2);
    elseif terms.TermType(j) == "Constant", value = value + coef;
    end
end
end
function t = empty_results()
t = table(zeros(0,1),strings(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),false(0,1),false(0,1),false(0,1),false(0,1),zeros(0,1),zeros(0,1),strings(0,1),strings(0,1), ...
    'VariableNames', {'Hour','TransmissionID','Type','LimitUnit','FlowMin','ModelFlowMW','ACExpressionMW','FlowMax','AtLowerLimit','AtUpperLimit','ModelConstraintViolated','ACExpressionOutsideMWBand','MuLower','MuUpper','EnforcementModel','LimitSource'});
end
