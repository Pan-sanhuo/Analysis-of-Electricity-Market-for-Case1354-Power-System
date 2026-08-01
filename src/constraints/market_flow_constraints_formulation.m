function om = market_flow_constraints_formulation(om, mpopt, args)
%MARKET_FLOW_CONSTRAINTS_FORMULATION Add FlowMin <= A*x <= FlowMax in MW.
% Branch terms use MATPOWER's DC flow linearization; generator terms use Pg.
% This is exact for DC OPF and a declared DC-linear market approximation in AC OPF.
mpc = om.get_mpc();
if ~isfield(mpc, 'marketFlowConstraints') || isempty(mpc.marketFlowConstraints), return; end
spec = mpc.marketFlowConstraints;
terms = mpc.marketFlowTerms;
[baseMVA, bus, branch] = deal(mpc.baseMVA, mpc.bus, mpc.branch);
[~, Bf, ~, Pfinj] = makeBdc(baseMVA, bus, branch);
nb = size(bus, 1); ng = size(mpc.gen, 1); nc = height(spec);
Ava = sparse(nc, nb); Apg = sparse(nc, ng);
lower = spec.FlowMinMW / baseMVA;
upper = spec.FlowMaxMW / baseMVA;
for k = 1:nc
    row = terms.ConstraintRow == k;
    tk = terms(row, :);
    for j = 1:height(tk)
        c = tk.Coefficient(j);
        if tk.TermType(j) == "Branch"
            e = tk.ElementIndex(j);
            Ava(k, :) = Ava(k, :) + c * Bf(e, :);
            lower(k) = lower(k) - c * Pfinj(e);
            upper(k) = upper(k) - c * Pfinj(e);
        elseif tk.TermType(j) == "Generator"
            Apg(k, tk.ElementIndex(j)) = Apg(k, tk.ElementIndex(j)) + c;
        elseif tk.TermType(j) == "Constant"
            lower(k) = lower(k) - c / baseMVA;
            upper(k) = upper(k) - c / baseMVA;
        end
    end
end
om.add_lin_constraint('market_flow', [Ava Apg], lower, upper, {'Va', 'Pg'});
end
