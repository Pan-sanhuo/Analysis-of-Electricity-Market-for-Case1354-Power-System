function results = market_flow_constraints_int2ext(results, mpopt, args)
%MARKET_FLOW_CONSTRAINTS_INT2EXT Preserve market-constraint prices in $/MW.
if ~isfield(results, 'marketFlowConstraints') || isempty(results.marketFlowConstraints), return; end
results.marketFlow.muLower = results.lin.mu.l.market_flow / results.baseMVA;
results.marketFlow.muUpper = results.lin.mu.u.market_flow / results.baseMVA;
results.marketFlow.constraint = results.marketFlowConstraints;
if isfield(results.order, 'ext') && isfield(results.order.ext, 'marketFlowTerms')
    results.marketFlow.terms = results.order.ext.marketFlowTerms;
end
end
