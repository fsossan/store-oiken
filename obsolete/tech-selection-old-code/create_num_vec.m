function num_vec = create_num_vec(x)
num_vec = [];

for i = 1:numel(x)
num_vec = [num_vec;arrayfun(@(x) str2double(x),string(x(i)))];
end