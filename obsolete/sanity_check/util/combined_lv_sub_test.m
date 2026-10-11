% substation and grid combined
function [net,graph_data] = combined_lv_sub(MV_LV_sub,LV_grid,Zb)
graph_data = {};
% MV-LV substation
[MV_LV_sub slack_node_id] = transformer_modeling(MV_LV_sub);
off_switch_idx = find(MV_LV_sub.On_OffState==0);
MV_LV_sub(off_switch_idx,:)=[];
from_lv_sub = MV_LV_sub.From;
to_lv_sub = MV_LV_sub.To;
label_lv_sub = string((MV_LV_sub.Object));
demand_index_MV = zeros(numel(from_lv_sub),1);
% plot_topology(from_lv_sub,to_lv_sub,demand_index_MV,label_lv_sub,true)

% LV grid
from_lv =LV_grid.From;
to_lv = LV_grid.To;
label_lv_grid = repmat(" ",size(LV_grid.Line,1),size(LV_grid.Line,2));
demand_index_LV  = (LV_grid.PLmax_kW_>0);
% plot_topology(from_lv,to_lv,demand_index_LV,label_lv_grid,false);

% combined
from_comb = [from_lv_sub;from_lv];
to_comb   = [to_lv_sub;to_lv];
demand_index_comb = [demand_index_MV;demand_index_LV];
label_comp = [extractBetween(label_lv_sub,1,1);label_lv_grid];
% transformer rating label
for r=1:height(label_lv_sub)
    if isequal(label_comp(r),"T")
        label_comp(r)="T"+MV_LV_sub.RatedPower_kVA_(r);

    end
    if isequal(label_comp(r),"S")
    label_comp(r) = "";
    end
end

[from to] = plot_error_topology (from_comb,to_comb,slack_node_id,demand_index_comb,label_comp,true);
graph_data.from_comb = from_comb;
graph_data.to_comb = to_comb;
graph_data.demand_index_comb = demand_index_comb;
graph_data.label_comp = label_comp;
graph_data.slack_node_id=slack_node_id;
%

Line = [(MV_LV_sub.Object);string(LV_grid.Line)];
Length = [0.01+(zeros(height(MV_LV_sub),1));LV_grid.Length_m_];
R_pu = [MV_LV_sub.R_p_u_;(LV_grid.R_Ohm_km_.*LV_grid.Length_m_/1e3)./Zb];
X_pu = [MV_LV_sub.X_p_u_;(LV_grid.X_Ohm_km_.*LV_grid.Length_m_/1e3)./Zb];
MV_amp_rat = MV_ampacity(MV_LV_sub);
Ampacity = [MV_amp_rat';LV_grid.Ampacity_A_];
P_rat = [zeros(height(MV_LV_sub),1);LV_grid.PLmax_kW_];
Q_rat = [zeros(height(MV_LV_sub),1);LV_grid.QLmax_kVar_];
PV_rat = [zeros(height(MV_LV_sub),1);LV_grid.Pg_kW_];

net = table(from,to,Line,Length,R_pu,X_pu,Ampacity,P_rat,Q_rat,PV_rat);

    function [MV_LV_sub,slack_node_id] = transformer_modeling(MV_LV_sub)
        
        [~,prim_sw_id]=setdiff(MV_LV_sub.From,MV_LV_sub.To);

          if all(MV_LV_sub(prim_sw_id,:).To==MV_LV_sub(prim_sw_id,:).To(1))==1

             slack_node_id = MV_LV_sub(prim_sw_id,:).To(1);
               MV_LV_sub(prim_sw_id,:)=[]; % delete the switches tactic (so far

         else 
             slack_node_id = [];
         end 
         
    end

    function MV_amp_rat=MV_ampacity (MV_LV_sub)
        label_lv_sub = extractBetween(string((MV_LV_sub.Object)),1,1);
        for r=1:height(MV_LV_sub)
            if isequal(label_lv_sub(r),"T")
                MV_amp_rat(r) = (MV_LV_sub.RatedPower_kVA_(r))/(sqrt(3)*MV_LV_sub.To_Voltage_kV_(r));
            else
                MV_amp_rat(r) = 1500;
            end
        end
    end





end