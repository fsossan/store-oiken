% One-off: write the calendar day of each training day of the demand data
% (data/demand_train_days.csv), so the Python fit can filter weekdays/seasons.
here = fileparts(mfilename('fullpath'));
S = load(fullfile(here, '..', '..', 'tech-selection', 'data', 'external', 'load_consumption_train_heapo.mat'));
X = S.training_data.X; t = S.training_data.time;
steps = size(X, 1);
d = dateshift(t(1:steps:end), 'start', 'day');
T = table(string(d(:), 'yyyy-MM-dd'), 'VariableNames', {'date'});
writetable(T, fullfile(here, '..', 'data', 'demand_train_days.csv'));
fprintf('%d days from %s to %s\n', height(T), T.date(1), T.date(end));
