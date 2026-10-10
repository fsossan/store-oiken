function read_data_sierre()

%% reading LV Grid
warning off; % ignore excel warning (not important)
Sierre = {};
disp(' --- reading Sierre data --')
workbook = '1_LV Grid_Sierre.xlsx';
[~,LV_grid_id]=xlsfinfo(workbook);
for k=1:numel(LV_grid_id)
opts = detectImportOptions(workbook, 'Sheet', LV_grid_id{k});
opts = setvartype(opts, {'From', 'To'}, 'string'); % or 'char'
LV_grid{k} = readtable(workbook, opts);
end
Sierre.LV_grid = LV_grid;
Sierre.LV_grid_id = LV_grid_id;

%% readubg MV-LV substation
workbook2 = '3_MV-LV Substation_Sierre.xlsx';
[~,MV_LV_sub_id]=xlsfinfo(workbook2);
for k=1:numel(MV_LV_sub_id)
opts = detectImportOptions(workbook2, 'Sheet', MV_LV_sub_id{k});
opts = setvartype(opts, {'From', 'To'}, 'string'); % or 'char'
MV_LV_sub{k} = readtable(workbook2, opts);
end
Sierre.MV_LV_sub = MV_LV_sub;
Sierre.MV_LV_sub_id =MV_LV_sub_id;

%% reading MV grid

workbook3 = '2_MV Grid_Sierre.xlsx';
[~,MV_grid_id]=xlsfinfo(workbook3);
for k=1:numel(MV_grid_id)
opts = detectImportOptions(workbook3, 'Sheet', MV_grid_id{k});
opts = setvartype(opts, {'From', 'To'}, 'string'); % or 'char'
MV_grid{k} = readtable(workbook3, opts);
end
Sierre.MV_grid = MV_grid;
Sierre.MV_grid_id = MV_grid_id;

%% reading MV stations (switches)

workbook4 = '4_MV Stations_Sierre.xlsx';
[~,MV_station_id]=xlsfinfo(workbook4);
for k=1:numel(MV_station_id)
opts = detectImportOptions(workbook4, 'Sheet', MV_station_id{k});
opts = setvartype(opts, {'From', 'To'}, 'string'); % or 'char'
MV_station{k} = readtable(workbook4, opts);
end
Sierre.MV_station = MV_station;
Sierre.MV_station_id = MV_station_id;

%% reading HV-MV stations 

workbook5 = '5_HV-MV Substations_Sierre.xlsx';
[~,MV_HV_sub_id]=xlsfinfo(workbook5);
for k=1:numel(MV_HV_sub_id)
opts = detectImportOptions(workbook5, 'Sheet', MV_HV_sub_id{k});
opts = setvartype(opts, {'From', 'To'}, 'string'); % or 'char'
MV_HV_sub{k} = readtable(workbook5, opts);
end
Sierre.MV_HV_sub = MV_HV_sub;
Sierre.MV_HV_sub_id = MV_HV_sub_id;

filename=('Sierre_dat.mat')
save(fullfile(pwd,'network_data/mat_data',filename),'Sierre');

disp(' --- Sierre data reading data COMPLETE --')
end