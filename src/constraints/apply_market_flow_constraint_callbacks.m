function mpc = apply_market_flow_constraint_callbacks(mpc)
%APPLY_MARKET_FLOW_CONSTRAINT_CALLBACKS Enable named FlowMin/FlowMax constraints.
if ~isfield(mpc, 'marketFlowConstraints') || isempty(mpc.marketFlowConstraints), return; end
mpc = add_userfcn(mpc, 'ext2int', @market_flow_constraints_ext2int);
mpc = add_userfcn(mpc, 'formulation', @market_flow_constraints_formulation);
mpc = add_userfcn(mpc, 'int2ext', @market_flow_constraints_int2ext);
end
