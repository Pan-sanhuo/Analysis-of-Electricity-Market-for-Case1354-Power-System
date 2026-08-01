function mpc = market_flow_constraints_ext2int(mpc, mpopt, args)
%MARKET_FLOW_CONSTRAINTS_EXT2INT Convert external branch/gen rows to MATPOWER indices.
% The source workbook uses named assets.  The model stores resolved external
% rows and converts them here, after MATPOWER has removed off-line elements.
if ~isfield(mpc, 'marketFlowTerms') || isempty(mpc.marketFlowTerms), return; end
terms = mpc.marketFlowTerms;
mpc.order.ext.marketFlowTerms = terms;

branchMap = zeros(size(mpc.order.ext.branch, 1), 1);
branchMap(mpc.order.branch.status.on) = (1:size(mpc.branch, 1)).';
genMap = zeros(size(mpc.order.ext.gen, 1), 1);
genMap(mpc.order.gen.status.on) = (1:size(mpc.gen, 1)).';

for k = 1:height(terms)
    if terms.TermType(k) == "Branch"
        terms.ElementIndex(k) = map_index(branchMap, terms.ElementIndex(k));
    elseif terms.TermType(k) == "Generator"
        terms.ElementIndex(k) = map_index(genMap, terms.ElementIndex(k));
    end
end
terms = terms(terms.ElementIndex > 0 | terms.TermType == "Constant", :);
mpc.marketFlowTerms = terms;
end

function i = map_index(map, i)
i = round(i);
if ~isfinite(i) || i < 1 || i > numel(map), i = 0; else, i = map(i); end
end
