function Sierre = PV_EV_allocation_SFOE_based (Sierre)
%% Allocation of PV and EV from national (SFOE-like) scenario to DSO and LV networks
% - National -> DSO scaling: population ratio
% - DSO -> LV network allocation: proportional to total installed power (sum PLmax)
% - PV within each LV network: proportional to nodal PLmax
% - EV within each LV network: proportional to nodal PLmax + largest remainder (integer)



% %% Load data
% load('Sierre_v2.mat');   % expects Sierre.LV_grid as cell array of tables

%% Scenario (SFOE-like) inputs
scenario.year         = 2040;
scenario.PV_share     = 0.35;        % PV penetration as fraction of total installed/peak demand (proxy)
scenario.EV_national  = 2.5e6;       % national EV fleet (vehicles)
scenario.pop_national = 10.0154e6;   % national population
scenario.pop_DSO      = 55332;       % DSO population (Sierre)
scenario.seed         = 12345;       % kept for reproducibility incase randomization is added later)

%% --- Step 1: National -> DSO scaling (population ratio)
EV_DSO_total = scenario.EV_national * (scenario.pop_DSO / scenario.pop_national);
EV_DSO_total = round(EV_DSO_total);  % EVs are discrete; keep total integer

%% --- Step 2: DSO -> LV network weights (total installed power per LV network)
G = numel(Sierre.LV_grid);          % number of LV networks
Pnet_vec = zeros(G,1);              % network weight = sum of nodal PLmax (kW)

for g = 1:G
    T = Sierre.LV_grid{g};
    Pnet_vec(g) = sum(T.PLmax_kW_); % includes zeros if present; OK
end

Pnet_total = sum(Pnet_vec);

% PV capacity per LV network (continuous): PV_share * network installed power
PV_net_kW = scenario.PV_share * Pnet_vec;

% EV per LV network (discrete): proportional to network installed power + largest remainder
EV_net_frac  = EV_DSO_total * (Pnet_vec / Pnet_total);
EV_net_floor = floor(EV_net_frac);
remainder    = EV_net_frac - EV_net_floor;

missing = EV_DSO_total - sum(EV_net_floor);  % how many EVs still need to be assigned
[~, idxSort] = sort(remainder, 'descend');

EV_net = EV_net_floor;
if missing > 0
    EV_net(idxSort(1:missing)) = EV_net(idxSort(1:missing)) + 1;
end


%% --- Step 3: Within-network allocation
% PV within LV network: proportional to nodal PLmax among active nodes
% EV within LV network: proportional to nodal PLmax among active nodes + largest remainder

for g = 1:G
    T = Sierre.LV_grid{g};
    N = height(T);

    active = (T.PLmax_kW_ > 0);  % eligible nodes
    PL_active = T.PLmax_kW_(active);

    % --- PV allocation within network (continuous)
    PV_kW_ = zeros(N,1);
    if any(active)
        PV_kW_(active) = PV_net_kW(g) * (PL_active / sum(PL_active));
    end
    T.PV_kW_ = PV_kW_;

    % --- EV allocation within network (integer)
    EV_count = zeros(N,1);
    if any(active) && EV_net(g) > 0
        EV_frac_node  = EV_net(g) * (PL_active / sum(PL_active));
        EV_floor_node = floor(EV_frac_node);
        rem_node      = EV_frac_node - EV_floor_node;

        missing_node = EV_net(g) - sum(EV_floor_node);
        [~, idxNode] = sort(rem_node, 'descend');

        EV_active = EV_floor_node;
        if missing_node > 0
            EV_active(idxNode(1:missing_node)) = EV_active(idxNode(1:missing_node)) + 1;
        end

        EV_count(active) = EV_active;
    end
    T.EV_count = EV_count;

    % write back
    Sierre.LV_grid{g} = T;
end

%% ===================== VERIFICATION =====================

% 1) EV mass conservation (DSO level)
% EV_total_check = 0;
% for g = 1:G
%     EV_total_check = EV_total_check + sum(Sierre.LV_grid{g}.EV_count);
% end
% fprintf('EV target (DSO): %d | EV allocated: %d\n', EV_DSO_total, EV_total_check);
% 
% 2) EV mass conservation (network level)
% EV_net_check = zeros(G,1);
% for g = 1:G
%     EV_net_check(g) = sum(Sierre.LV_grid{g}.EV_count);
% end
% fprintf('Max |EV_net_check - EV_net| = %d\n', max(abs(EV_net_check - EV_net)));
% 
% 3) PV mass conservation (total PV share achieved)
% PV_total_check = 0;
% PL_total_check = 0;
% for g = 1:G
%     T = Sierre.LV_grid{g};
%     PV_total_check = PV_total_check + sum(T.PV_kW_);
%     PL_total_check = PL_total_check + sum(T.PLmax_kW_);
% end
% fprintf('PV share target: %.6f | Achieved: %.6f\n', ...
%     scenario.PV_share, PV_total_check / PL_total_check);
% 
% 4) Basic consistency checks
% for g = 1:G
%     T = Sierre.LV_grid{g};
%     active = (T.PLmax_kW_ > 0);
% 
%     EVs only on active nodes and integer-valued
%     assert(all(T.EV_count(~active) == 0), 'EV assigned to inactive nodes in network %d', g);
%     assert(all(mod(T.EV_count(active), 1) == 0), 'Non-integer EV count in network %d', g);
% 
%     PV only on active nodes (optional, depends on your definition)
%     assert(all(T.PV_kW_(~active) == 0), 'PV assigned to inactive nodes in network %d', g);
% end
% disp('All verification checks passed.');
% 
% % Optional: quick plots for one LV network
% g = 1;
% T = Sierre.LV_grid{g};
% active = T.PLmax_kW_ > 0;
% 
% figure; histogram(T.PLmax_kW_(active)); title(sprintf('Network %d: PLmax (active nodes)', g));
% figure; histogram(T.PV_kW_(active));    title(sprintf('Network %d: PV allocated (active nodes)', g));
% figure; histogram(T.EV_count(active));  title(sprintf('Network %d: EV count (active nodes)', g));
end 