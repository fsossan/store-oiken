clc; close all, clear

vars = {'C_curt_CHF_kWh_','PV_curt_kWh_','E_kWh_','S_kW_','CostFunctionKCHF_'};
opts = detectImportOptions('Copy_of_tech-selection-pv-curt.csv');
opts = setvartype(opts,vars,'double');
opts = setvaropts(opts,vars,'DecimalSeparator',',');

data = readtable('Copy_of_tech-selection-pv-curt.csv',opts);
c_curt  = data.C_curt_CHF_kWh_;
PV_curt = data.PV_curt_kWh_;
E_kWh   = data.E_kWh_;
S_kW    = data.S_kW_;
cos_tot = data.CostFunctionKCHF_;
cos_tot(1,1) = 0;


figure;

yyaxis left
plot(c_curt, PV_curt, '-o', 'LineWidth', 1.5);
ylabel('Curtailed PV energy (kWh/day)');
yyaxis right
plot(c_curt, E_kWh, '-s', 'LineWidth', 1.5);
ylabel('Enom (kWh)');
xlabel('C_{curt} (CHF/kWh)');
grid on;
figure
plot(c_curt, cos_tot, '-d', 'LineWidth', 1.5, 'Color', [0.49 0.18 0.56]);
xlabel('C_{curt} (CHF/kWh)');
ylabel('total cost (kCHF)');
% title('Storage duration selected across sweep');
grid on;



