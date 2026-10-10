function substation_analysis(Sion, Sierre)
% substation_analysis - Analyses substation tables across all LV networks
% Extracts transformer count, rated power, switch states, missing values, voltage levels
% Also saves a flat transformer_data table for imputation analysis

combined_sub     = [Sion.MV_LV_sub     Sierre.MV_LV_sub];
combined_subs_ID = [Sion.MV_LV_sub_id  Sierre.MV_LV_sub_id];
n_networks = numel(combined_sub);

% Preallocate results table
substation_ID       = zeros(n_networks, 1);
n_transformers      = zeros(n_networks, 1);
n_switches          = zeros(n_networks, 1);
n_fuses             = zeros(n_networks, 1);
n_open_switches     = zeros(n_networks, 1);
total_rated_power   = zeros(n_networks, 1);
max_rated_power     = zeros(n_networks, 1);
missing_R           = zeros(n_networks, 1);
missing_X           = zeros(n_networks, 1);
missing_power       = zeros(n_networks, 1);
hv_voltage          = zeros(n_networks, 1);
lv_voltage          = zeros(n_networks, 1);
n_total_objects     = zeros(n_networks, 1);

% Initialize transformer detail table BEFORE the loop
transformer_data = table();

for i = 1:n_networks
    tbl = combined_sub{i};

    % Substation ID
    sub_str = combined_subs_ID{i};
    substation_ID(i) = str2double(regexp(sub_str, '\d+', 'match', 'once'));

    % Object type classification via prefix in Object column
    objects        = vertcat(tbl.Object);
    is_transformer = contains(objects, 'Tr_');
    is_switch      = contains(objects, 'SW_') & ~contains(objects, 'Fus');
    is_fuse        = contains(objects, 'Fus') | ...
                     (contains(tbl.From, 'Fus') | contains(tbl.To, 'Fus'));

    n_transformers(i)  = sum(is_transformer);
    n_switches(i)      = sum(is_switch);
    n_fuses(i)         = sum(is_fuse);
    n_total_objects(i) = height(tbl);

    % Open switches
    n_open_switches(i) = sum(tbl.On_OffState == 0);

    % Transformer-specific stats
    tr_rows = tbl(is_transformer, :);

    if ~isempty(tr_rows)
        % Aggregate stats
        total_rated_power(i) = sum(tr_rows.RatedPower_kVA_);
        max_rated_power(i)   = max(tr_rows.RatedPower_kVA_);
        hv_voltage(i) = max(tr_rows.From_Voltage_kV_(~isnan(tr_rows.From_Voltage_kV_)));
        lv_voltage(i) = min(tr_rows.To_Voltage_kV_(~isnan(tr_rows.To_Voltage_kV_)));

        % Accumulate flat transformer detail table
        n_tr       = height(tr_rows);
        sub_id_vec = repmat(substation_ID(i), n_tr, 1);
        tr_id      = tr_rows.Object;
        R_tr       = tr_rows.R_p_u_;
        X_tr       = tr_rows.X_p_u_;
        kVA        = tr_rows.RatedPower_kVA_;
        HV         = tr_rows.From_Voltage_kV_;
        LV         = tr_rows.To_Voltage_kV_;

        tr_batch = table(sub_id_vec, tr_id, R_tr, X_tr, kVA, HV, LV, ...
            'VariableNames', {'substation_ID','transformer_ID','R_pu','X_pu','kVA','HV_kV','LV_kV'});

        transformer_data = [transformer_data; tr_batch];
    end

    % Missing value detection (0 or NaN treated as missing)
    missing_R(i)     = sum((tbl.R_p_u_ == 0     | isnan(tbl.R_p_u_))     & ~is_switch & ~is_fuse);
    missing_X(i)     = sum((tbl.X_p_u_ == 0     | isnan(tbl.X_p_u_))     & ~is_switch & ~is_fuse);
    missing_power(i) = sum((tbl.RatedPower_kVA_ == 0 | isnan(tbl.RatedPower_kVA_)) & is_transformer);
end

% Build network-level results table
results = table(substation_ID, n_total_objects, n_transformers, n_switches, ...
                n_fuses, n_open_switches, total_rated_power, max_rated_power, ...
                missing_R, missing_X, missing_power, hv_voltage, lv_voltage);

% Save transformer detail table
save(fullfile('output', 'transformer_data.mat'), 'transformer_data');
fprintf('transformer_data saved: %d transformers across %d networks\n', ...
    height(transformer_data), n_networks);

% Save markdown
md_substation(results);
end