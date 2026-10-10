import pyodbc
import pandas as pd
import numpy as np
import math
import warnings

warnings.filterwarnings(
    "ignore",
    category=UserWarning,
    message="pandas only supports SQLAlchemy connectable")

City='Sion'
# pyodbc.drivers()
cnxn = pyodbc.connect('DRIVER={ODBC Driver 17 for SQL Server};SERVER=VS-W12540\\SQLEXPRESS;DATABASE=TNDB_ESR_TEST;Trusted_Connection=yes;TrustServerCertificate=yes')

cursor = cnxn.cursor()
sor = cnxn.cursor()

query_NodCnx = "SELECT  id_NOD, cop.id_COP, code_NOD, nom_NOD,idNDE_COP, id_BRA ,code_BRA, longueur_BRA, idBCL_BRA, idNCL_NOD, etatFlux_COP, \
coordNationalX_NOD, coordNationalY_NOD, cop.idNIV_COP \
FROM  noeud_NOD nod  \
INNER JOIN composant_COP cop ON cop.idNOD_COP = nod.id_NOD \
INNER JOIN connecteurComplexe_CNX cnx1 ON cnx1.idCOP_CNX = cop.id_COP \
INNER JOIN connecteurComplexe_CNX cnx2 ON cnx1.idCNX_CNX= cnx2.id_CNX \
INNER JOIN branche_BRA bra ON bra.id_BRA = cnx2.idBRA_CNX" 
df_NodCnx = pd.read_sql_query(query_NodCnx, cnxn)
#df_NodCnx = df_NodCnx.dropna(subset=["code_NOD"]) # Drop rows that has NaN values on selected columns

########################################################
query_Coffret_Gen = "SELECT cof.PL_COF, idNOD_COF, cof.clientConsommationAnnuelCompteur_COF, puissanceMax_EPR FROM coffretIntroduction_COF cof \
INNER JOIN noeud_NOD nod ON nod.id_NOD = cof.idNOD_COF \
LEFT JOIN composant_COP cop ON cop.idNOD_COP = nod.id_NOD \
INNER JOIN elementProduction_EPR epr ON epr.idCOP_EPR = cop.id_COP \
WHERE \
  epr.idCOP_EPR IS NOT NULL "

df_Coffret_Gen= pd.read_sql_query(query_Coffret_Gen, cnxn)  # Generators
idNOD_COF_Gen=df_Coffret_Gen['idNOD_COF'].values
###############################################################
query_Coffret_Load = "SELECT cof.PL_COF, cof.idNOD_COF, cof.clientConsommationAnnuelCompteur_COF,  courantConsigne_COF, courantFinance_COF \
                        FROM coffretIntroduction_COF cof \
                        WHERE clientConsommationAnnuelCompteur_COF <> 0 AND clientConsommationAnnuelCompteur_COF IS NOT NULL" 

df_Coffret_Load= pd.read_sql_query(query_Coffret_Load, cnxn)  
#print (df_Coffret_Load)
idNOD_COF_Load=df_Coffret_Load['idNOD_COF'].values 
#################################################################
query_Cable ="SELECT  id_BRA, id_CAT, descriptionLongue_CAT,  longueur_BRA, resLineique_CAT, indLineique_CAT, capLineique_CAT \
type_CAT,[section_CAT] ,[courantAdmissible_CAT] \
FROM  branche_BRA bra \
INNER JOIN cable_CAB cab ON cab.idBRA_CAB = bra.id_BRA \
INNER JOIN dbo.V_CableType cType ON cType.id_CAT = cab.idCAT_CAB \
INNER JOIN niveau_NIV niv ON niv.id_NIV = cType.idNIV_CAT" 

df_Cable= pd.read_sql_query(query_Cable, cnxn)

###################################################3
query_CableType ="SELECT [id_CAT],type_CAT,[section_CAT] ,[courantAdmissible_CAT] ,[resLineique_CAT] ,[indLineique_CAT],[capLineique_CAT] \
      ,[uniTri_CAT] ,[materiel_CAT] ,valeur_NIV,[section_CAT] \
      FROM [TNDB_ESR_TEST].[dbo].[nCableType_CAT] CAT   \
      INNER JOIN niveau_NIV NV ON  cat.idNIV_CAT=NV.id_NIV" 

df_CableType= pd.read_sql_query(query_CableType, cnxn)

############################################################

query_OHL="SELECT id_BRA, idLTY_LIG,longueur_BRA,resLineique_LTY, indLineique_LTY, capLineique_LTY, section_LTY, courantAdmissible_LTY, type_LTY, materiel_LTY \
FROM  branche_BRA bra \
INNER JOIN ligne_LIG lig ON lig.idBRA_LIG = bra.id_BRA \
INNER JOIN dbo.nLigneType_LTY lType ON lType.id_LTY = lig.idLTY_LIG \
INNER JOIN niveau_NIV niv ON niv.id_NIV = lType.idNIV_LTY"\

df_OHL= pd.read_sql_query(query_OHL, cnxn)

#################################################################

query_OHLType="SELECT [id_LTY],[type_LTY],[courantAdmissible_LTY],[resLineique_LTY],[indLineique_LTY],[capLineique_LTY],[section_LTY],[typeObjet_LTY],[uniTri_LTY] \
      ,[materiel_LTY], [section_LTY]\
      ,[idNIV_LTY], valeur_NIV \
  FROM [TNDB_ESR_TEST].[dbo].[nLigneType_LTY] \
  INNER JOIN niveau_NIV niv ON niv.id_NIV = idNIV_LTY"
df_OHLType= pd.read_sql_query(query_OHLType, cnxn)


##########################################################
query_NODE_Sierre_MT="SELECT id_NOD FROM noeud_NOD WHERE IDRED_NOD >= 95 and idNCL_NOD=1"
df_NODE_Sierre_MT= pd.read_sql_query(query_NODE_Sierre_MT, cnxn)
######
query_NODE_Sierre_HT="SELECT id_NOD FROM noeud_NOD WHERE idNCL_NOD=3 and IDRED_NOD >= 95" 
df_NODE_Sierre_HT= pd.read_sql_query(query_NODE_Sierre_HT, cnxn)

###########################################################################
query_NODE_Sion_MT="SELECT id_NOD FROM noeud_NOD WHERE idRED_NOD < 95 AND idNCL_NOD = 1 "
df_NODE_Sion_MT= pd.read_sql_query(query_NODE_Sion_MT, cnxn)
######
query_NODE_Sion_HT="SELECT id_NOD FROM noeud_NOD WHERE idNCL_NOD=3 and IDRED_NOD < 95"
df_NODE_Sion_HT= pd.read_sql_query(query_NODE_Sion_HT, cnxn)
##########################################################################

query_CompCnx = "SELECT cop1.idNOD_COP, cop1.id_COP as id_COP1, cop2.id_COP as id_COP2  \
    FROM \
    dbo.composant_COP cop1 inner join \
    dbo.connecteurComplexe_CNX cnx1 on cnx1.idCOP_CNX = cop1.id_COP inner join\
    dbo.connecteurComplexe_CNX cnx2 on cnx1.idCNX_CNX = cnx2.id_CNX inner join\
    dbo.composant_COP cop2 on cnx2.idCOP_CNX = cop2.id_COP \
    WHERE cop1.id_COP < cop2.id_COP"
df_CompCnx = pd.read_sql_query(query_CompCnx, cnxn)
#####################################################################
#####################################################################
query_Comp = "SELECT [id_COP] ,[idCCL_COP],[idNOD_COP],[idNDE_COP],[idNIV_COP],[etatFlux_COP]\
  FROM [TNDB_ESR_TEST].[dbo].[composant_COP]"
df_Comp = pd.read_sql_query(query_Comp, cnxn)
#####################################################################
query_Trans2="SELECT [idCOP_TRF],[idTTY_TRF],[perteCuivre_TRF],[perteFer_TRF],[uCC_TRF],[rapportTI_TRF],[puissance_TRF],[tensionSecondaire_TRF] \
     ,[tensionPrimaire_TRF],[couplage_TRF],[posInserateur_TRF], [nbPosInserateur_TRF] ,[deltaUPosInserateur_TRF] \
  FROM [TNDB_ESR_TEST].[dbo].[transformateur_TRF]"
df_Trans2= pd.read_sql_query(query_Trans2, cnxn)  # ] ; [id_TTY],[nom_TTY],[puissance_TTY],[idTTG_TTY],[rapportTension_TTY],[tensionSecondaire_TTY]
########################3
###################################################
query_InfBus="SELECT [id_MBA], cop.id_COP,cop.idNOD_COP,[idCOP_MBA],[ICCTri_MBA],[argumentCCTri_MBA],[ICCMono_MBA],[argumentCCMono_MBA]\
  FROM [TNDB_ESR_TEST].[dbo].[mesureBarre_MBA] MBA\
  INNER JOIN composant_COP cop ON cop.id_COP = MBA.idCOP_MBA "
df_InfBus= pd.read_sql_query(query_InfBus, cnxn) 

node_coord_by_id = {}
node_coord_by_code = {}
for row in df_NodCnx[['id_NOD', 'coordNationalX_NOD', 'coordNationalY_NOD']].itertuples(index=False):
    node_id = row.id_NOD
    if pd.isna(node_id):
        continue
    try:
        key = int(round(float(node_id)))
    except (TypeError, ValueError):
        continue
    x_val = np.nan if pd.isna(row.coordNationalX_NOD) else float(row.coordNationalX_NOD)
    y_val = np.nan if pd.isna(row.coordNationalY_NOD) else float(row.coordNationalY_NOD)
    if key not in node_coord_by_id or any(np.isnan(node_coord_by_id.get(key, (np.nan, np.nan)))):
        node_coord_by_id[key] = (x_val, y_val)

for row in df_NodCnx[['code_NOD', 'coordNationalX_NOD', 'coordNationalY_NOD']].itertuples(index=False):
    code = row.code_NOD
    if not isinstance(code, str):
        continue
    code_key = code.strip()
    if not code_key:
        continue
    x_val = np.nan if pd.isna(row.coordNationalX_NOD) else float(row.coordNationalX_NOD)
    y_val = np.nan if pd.isna(row.coordNationalY_NOD) else float(row.coordNationalY_NOD)
    if code_key not in node_coord_by_code or any(np.isnan(node_coord_by_code.get(code_key, (np.nan, np.nan)))):
        node_coord_by_code[code_key] = (x_val, y_val)


def _parse_numeric_identifier(value):
    if value is None:
        return None
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(numeric):
        return None
    return int(round(numeric))


def get_node_coordinates(node_label):
    if node_label is None:
        return (np.nan, np.nan)
    candidates = []
    if isinstance(node_label, str):
        base = node_label.strip()
        if not base:
            return (np.nan, np.nan)
        candidates.append(base)
        if base.startswith('N_'):
            candidates.append(base[2:].strip())
        if base.startswith('N '):
            candidates.append(base[1:].strip())
    else:
        candidates.append(node_label)

    for cand in candidates:
        numeric_id = _parse_numeric_identifier(cand)
        if numeric_id is None:
            continue
        coords = node_coord_by_id.get(numeric_id)
        if coords:
            x_val, y_val = coords
            return (
                np.nan if pd.isna(x_val) else x_val,
                np.nan if pd.isna(y_val) else y_val,
            )

    for cand in candidates:
        if not isinstance(cand, str):
            continue
        coords = node_coord_by_code.get(cand)
        if coords:
            x_val, y_val = coords
            return (
                np.nan if pd.isna(x_val) else x_val,
                np.nan if pd.isna(y_val) else y_val,
            )

    return (np.nan, np.nan)


def add_endpoint_coordinates(df):
    if not isinstance(df, pd.DataFrame):
        return df
    df_with_coords = df.copy()
    if 'From' in df_with_coords.columns:
        from_coords = df_with_coords['From'].apply(get_node_coordinates)
        df_with_coords['From_x'] = [coord[0] for coord in from_coords]
        df_with_coords['From_y'] = [coord[1] for coord in from_coords]
    else:
        df_with_coords['From_x'] = np.nan
        df_with_coords['From_y'] = np.nan
    if 'To' in df_with_coords.columns:
        to_coords = df_with_coords['To'].apply(get_node_coordinates)
        df_with_coords['To_x'] = [coord[0] for coord in to_coords]
        df_with_coords['To_y'] = [coord[1] for coord in to_coords]
    else:
        df_with_coords['To_x'] = np.nan
        df_with_coords['To_y'] = np.nan
    return df_with_coords

def StationPreProc(Node_id):
    CLNode=df_NodCnx.loc[df_NodCnx['id_NOD']==Node_id].idNCL_NOD.values[0]
    if CLNode==1:
        Vb1=0.4
        Vb2=16.8
        NT1='N_TrL_'
        NT2='N_TrM_'
        CL1=1
        CL2=2
        NJ1='N_JbL_'
        NJ2='N_JbM_'
        NS1='N_Fus_'
        NS2='N_SWM_'
    if CLNode in [3,5]:
        Vb1=16.8
        Vb2=65
        NT1='N_TrM_'
        NT2='N_TrH_'
        CL1=2
        CL2=3
        NJ1='N_JbM_'
        NJ2='N_JbH_'
        NS1='N_SWM_'
        NS2='N_SWH_'

    def indices(lst, item):
        return [i for i, x in enumerate(lst) if x == item]
    
    def CLNIV(iS):
        CompCL=df_Comp .loc[df_Comp ['id_COP']==iS]['idCCL_COP'].values[0]
        CompNIV=df_Comp .loc[df_Comp ['id_COP']==iS]['idNIV_COP'].values[0] 
        ComDEP=df_Comp.loc[df_Comp ['id_COP']==iS]['idNDE_COP'].values[0]  
        return [CompCL,CompNIV,ComDEP]

    df_CompCnxNode=df_CompCnx.loc[df_CompCnx['idNOD_COP']==Node_id]
    df_CompCnxNode=df_CompCnxNode.reset_index(drop=True)
    #print(df_CompCnxNode)
    ######################################
    #print(len(df_CompCnxNode))
    for iSw in range(0,len(df_CompCnxNode)):
        Comp1=df_CompCnxNode.iloc[iSw,1]
        Comp2=df_CompCnxNode.iloc[iSw,2]
        
        if (CLNIV(Comp1)[0]==16 and CLNIV(Comp2)[0]==17):
            Comp=Comp2
           
        elif (CLNIV(Comp2)[0]==16 and CLNIV(Comp1)[0]==17):
            Comp=Comp1
            
        else:
            continue
       
        indxC=df_Comp[(df_Comp.id_COP == Comp) ].index.values[0]  
        
       
        df_Comp.at[indxC ,'idCCL_COP'] = 2 
    ##########################################
    #print(df_CompCnxNode)
    df_CompCnxNode['UsageBus']=5
    df_CompCnxNode['Voltage'] =0
    df_CompCnxNode['CL_COP2'] =0
    COMPlist_0=list(df_CompCnxNode['id_COP1'].values)
    #print(COMPlist)
    COMPlist1_0=list(df_CompCnxNode['id_COP2'].values)
    #print(COMPlist)
    COMPlist_0.extend(COMPlist1_0)
    #print(COMPlist)
    COMPlist_unique_0=list(set(COMPlist_0))
    #print(COMPlist_unique)
        
    df_Cop1_0=list(df_CompCnxNode['id_COP1'])
    df_Cop2_0=list(df_CompCnxNode['id_COP2'])
    
    ######################### Toff: switch-transfo-bus bar
    for iS in COMPlist_unique_0:
        df_Cop_NodCnx=df_NodCnx.loc[df_NodCnx['id_COP']==iS]  ## it just applies to the SW located in the input of the substation
        if  len(df_Cop_NodCnx)!=0 :
            IndxC1=indices(df_Cop1_0,iS) 
            IndxC2=indices(df_Cop2_0,iS)
            IndexCut=[]
            IndexCut.extend(IndxC1)
            IndexCut.extend(IndxC2)
            
            ComDEP= CLNIV(iS)[2]
            flag=0
            ################3
            for ic in IndxC1:
                Comp=df_Cop2_0[ic]
                NIV_Comp=CLNIV(Comp)[1]
                DEP_Comp=CLNIV(Comp)[2]
                if (CLNIV(iS)[0] in [2,3,4,8,9,13])  and CLNIV(Comp)[0]==10:
                    flag+=1
                    CompT=Comp
                if (CLNIV(iS)[0] in [2,3,4,8,9,13])  and CLNIV(Comp)[0]==16:
                    flag+=1
                    CompBus=Comp
            for ic in IndxC2:
                Comp=df_Cop1_0[ic]
                NIV_Comp=CLNIV(Comp)[1]
                DEP_Comp=CLNIV(Comp)[2]
                if (CLNIV(iS)[0] in [2,3,4,8,9,13])  and CLNIV(Comp)[0]==10:
                    flag+=1
                    CompT=Comp
                if (CLNIV(iS)[0] in [2,3,4,8,9,13])  and CLNIV(Comp)[0]==16:
                    flag+=1
                    CompBus=Comp
                        
            if flag==2:
                #print('Hello')
                df_CompCnxNode=df_CompCnxNode.drop(index=IndexCut).reset_index(drop=True)
                #df_CompCnxNode.loc[len(df_CompCnxNode.index)] = [Node_id,CompBus,CompT,5,0,0]  # Tr connection to bus bar
                #df_CompCnxNode.loc[len(df_CompCnxNode.index)] = [Node_id,CompBus,iS,5,0,0]  # Sw connection to bus bar
                df_CompCnxNode.loc[len(df_CompCnxNode.index)] = [Node_id,CompT,iS,5,0,0]  # Sw connection to bus bar
                print (f"Switch Star Point WARNINTG with Transformer and Busbar: Switch id_COP={iS}; id_NOD={Node_id}.")
               
    #print(flag)
    ##########################
    ##########################
    #print(df_CompCnxNode)
    COMPlist=list(df_CompCnxNode['id_COP1'].values)
    #print(COMPlist)
    COMPlist1=list(df_CompCnxNode['id_COP2'].values)
    #print(COMPlist)
    COMPlist.extend(COMPlist1)
    #print(COMPlist)
    COMPlist_unique=list(set(COMPlist))
    #print(COMPlist_unique)
        
    df_Cop1=list(df_CompCnxNode['id_COP1'])
    df_Cop2=list(df_CompCnxNode['id_COP2'])
 ############### the switches in Toff  
    AddSW=[]
    for iSw in range(0,len(df_CompCnxNode)):
        Comp1=df_CompCnxNode.iloc[iSw,1]
        Comp2=df_CompCnxNode.iloc[iSw,2]
        if (CLNIV(Comp1)[0] in [2,3,4,8,9,13]) and (CLNIV(Comp2)[0] in [2,3,4,8,9,13]):  ### deleted 17
            AddSW.append({Comp1,Comp2})
    AddSW1=AddSW.copy()
    Hsw=[]
    for j in AddSW:
        AddSW1.remove(j)
        for i in AddSW1:
            Sec=j.intersection(i)
            if Sec!=set():
                Hsw.append(list(Sec)[0])
    HToff=list(set(Hsw))
    #########
    #print(HToff)
    #print(df_CompCnxNode)


    
#°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°
#########
    Cut_SW=[]
    Ciw=0
    for iSw in range(0,len(df_CompCnxNode)):
        Comp1=df_CompCnxNode.iloc[iSw,1]
        Comp2=df_CompCnxNode.iloc[iSw,2]
        NIV_Comp=CLNIV(Comp2)[1]
        DEP_Comp2=CLNIV(Comp2)[2]
        DEP_Comp1=CLNIV(Comp1)[2]
        Vb=Vb1/math.sqrt(3) if NIV_Comp==CL1 else Vb2/math.sqrt(3)
        Usage=2
        NS=NS1 if NIV_Comp==CL1 else NS2
        if (CLNIV(Comp1)[0] in [2,3,4,8,9,13]) and (CLNIV(Comp2)[0] in [2,3,4,8,9,13]):  ### deleted 17
            Comp=max([Comp1,Comp2])
            if Comp1 in HToff:
                Comp=Comp1
            if Comp2 in HToff:
                Comp=Comp2
        
            df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, 'N_MPt_'+str(Comp), DEP_Comp1, Usage,Vb, 0]  # middle point
            Ciw+=1
            df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, 'N_MPt_'+str(Comp), DEP_Comp2, Usage,Vb, 0]  # middle point
            Cut_SW.append(iSw)
            Ciw+=1
        
        ######################
        if (CLNIV(Comp1)[0] in [2,3,4,8,9,13]) and CLNIV(Comp2)[0]==17: 
            df_CompCnxNode.loc[len(df_CompCnxNode.index)] = [Node_id,NS+str(DEP_Comp2),DEP_Comp1,Usage,Vb,0]  # fixed connection
            Cut_SW.append(iSw)
            Ciw+=1
        if  CLNIV(Comp1)[0] ==17 and CLNIV(Comp2)[0] in [2,3,4,8,9,13]: 
            df_CompCnxNode.loc[len(df_CompCnxNode.index)] = [Node_id,NS+str(DEP_Comp1),DEP_Comp2,Usage,Vb,0]  # fixed connection
            Cut_SW.append(iSw)
            Ciw+=1
            
    df_CompCnxNode.drop_duplicates(inplace=True)
    df_CompCnxNode=df_CompCnxNode.drop(index=Cut_SW).reset_index(drop=True)
    #print(df_CompCnxNode)
    #######################3
    AddedTerm=[]
    TrBusDirecConnection=[]
    for iS in COMPlist_unique:
        #print(iS)
        IndxC1=indices(df_Cop1,iS) 
        IndxC2=indices(df_Cop2,iS)
        ComDEP= CLNIV(iS)[2]
        ################3
        if CLNIV(iS)[0]==10 and (iS in df_Cop1):
            DEP_iS=CLNIV(iS)[2]
            Usage=2
            for ic in IndxC1:
                Comp2=df_Cop2[ic]
                CL_Comp2=CLNIV(Comp2)[0]
                NIV_Comp2=CLNIV(Comp2)[1]
                DEP_Comp2=CLNIV(Comp2)[2]
                if CL_Comp2 !=16:
                    if NIV_Comp2==CL1:
                        Vb=Vb1/math.sqrt(3)
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), DEP_Comp2, Usage,Vb, 0]
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), DEP_iS,Usage,Vb,0]
                       # df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), iS]
                    elif NIV_Comp2==CL2:
                        Vb=Vb2/math.sqrt(3)
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT2+str(iS), DEP_Comp2, Usage,Vb,0]
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT2+str(iS), DEP_iS,Usage,Vb,0]
                      #  df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, 'N_TrM__'+str(iS), iS] 
               
                    df_CompCnxNode = df_CompCnxNode.drop(df_CompCnxNode[(df_CompCnxNode.id_COP1 == iS)& (df_CompCnxNode.id_COP2 == Comp2)].index).reset_index(drop=True)
                else:
                    TrBusDirecConnection.append(str(iS))
                    if NIV_Comp2==CL1:
                        Vb=Vb1/math.sqrt(3)
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NJ1+str(Comp2), DEP_iS,Usage,Vb,0]
                       # df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), iS]
                    if NIV_Comp2==CL2:
                        Vb=Vb2/math.sqrt(3)
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NJ2+str(Comp2), DEP_iS,Usage,Vb,0]
                       # df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), iS]
        if CLNIV(iS)[0]==10 and (iS in df_Cop2):
            DEP_iS=CLNIV(iS)[2]
            Usage=2
            for ic in IndxC2:
                Comp1=df_Cop1[ic]
                CL_Comp1=CLNIV(Comp1)[0]
                NIV_Comp1=CLNIV(Comp1)[1]
                DEP_Comp1=CLNIV(Comp1)[2]
                if CL_Comp1!=16:
                    if NIV_Comp1==CL1:
                        Vb=Vb1/math.sqrt(3)
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), DEP_Comp1,Usage,Vb,0]
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), DEP_iS,Usage,Vb,0]
                       # df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), iS]
                    if NIV_Comp1==CL2:
                        Vb=Vb2/math.sqrt(3)
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT2+str(iS), DEP_Comp1,Usage,Vb,0]
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT2+str(iS), DEP_iS,Usage,Vb,0]
                       # df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, 'N_TrM__'+str(iS), iS] 
            
                    df_CompCnxNode = df_CompCnxNode.drop(df_CompCnxNode[(df_CompCnxNode.id_COP2 == iS)& (df_CompCnxNode.id_COP1 == Comp1)].index).reset_index(drop=True)
                else:
                    TrBusDirecConnection.append(str(iS))
                    if NIV_Comp1==CL1:
                        Vb=Vb1/math.sqrt(3)
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NJ1+str(Comp1), DEP_iS,Usage,Vb,0]
                 
                       # df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), iS]
                    if NIV_Comp1==CL2:
                        Vb=Vb2/math.sqrt(3)
                        df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NJ2+str(Comp1), DEP_iS,Usage,Vb,0]
                     
                       # df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NT1+str(iS), iS]
        
        #######################           
            
      #  if CLNIV(iS)[0]==10:
          #  DEP_iS=CLNIV(iS)[2]
          ### this part to define virtual terminals for the single 
        #print(HToff)
        if CLNIV(iS)[0] in [2,3,4,8,9,13,17] and (COMPlist.count(iS)==1 or (COMPlist.count(iS)==2 and iS in HToff))  :      # 2 : Dj, 3 : Dj BT, 4 : Fusible, 8 : Sec, 9: Sec OHL, 13: couteau   
            Usage=2
            CompNIV= CLNIV(iS)[1]
            ComDEP= CLNIV(iS)[2]
            if CompNIV==CL1:
                Vb=Vb1/math.sqrt(3)
                #print(ComDEP)
                df_CompCnxNode.loc[len(df_CompCnxNode.index)] = [Node_id,NS1+str(ComDEP),ComDEP,Usage,Vb,0]   # str(ComDEP)
                AddedTerm.append(NS1+str(ComDEP))
            if CompNIV==CL2:
                Vb=Vb2/math.sqrt(3)
                df_CompCnxNode.loc[len(df_CompCnxNode.index)] = [Node_id,NS2+str(ComDEP),ComDEP,Usage,Vb,0]   #str(ComDEP)
                AddedTerm.append(NS2+str(ComDEP))
    
        if CLNIV(iS)[0] == 16 and (iS in df_Cop1):
            
            Usage=0   #Busbar
            for ic in IndxC1:
                Comp2=df_Cop2[ic]
                CL_Comp2=CLNIV(Comp2)[0]
                NIV_Comp2=CLNIV(Comp2)[1]
                DEP_Comp2=CLNIV(Comp2)[2]
                #print(NIV_Comp2)
                if NIV_Comp2==CL1 and CL_Comp2 in [2,3,4,8,9,13,17]:
                    Vb=Vb1/math.sqrt(3)
                    df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NJ1+str(iS), DEP_Comp2,Usage,Vb1/math.sqrt(3),0]
                elif NIV_Comp2==CL2 and CL_Comp2 in [2,3,4,8,9,13,17]:
                    Vb=Vb2/math.sqrt(3)
                    df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NJ2+str(iS), DEP_Comp2,Usage,Vb2/math.sqrt(3),0]
                df_CompCnxNode = df_CompCnxNode.drop(df_CompCnxNode[(df_CompCnxNode.id_COP1 == iS)& (df_CompCnxNode.id_COP2 == Comp2)].index).reset_index(drop=True)
       
        if CLNIV(iS)[0]== 16 and (iS in df_Cop2):
            
            Usage=0   #Busbar
            for ic in IndxC2:
                Comp1=df_Cop1[ic]
                CL_Comp1=CLNIV(Comp1)[0]
                NIV_Comp1=CLNIV(Comp1)[1]
                DEP_Comp1=CLNIV(Comp1)[2]
                #print(NIV_Comp1)
                if NIV_Comp1==CL1 and CL_Comp1 in [2,3,4,8,9,13,17]:
                    Vb=Vb1/math.sqrt(3)
                    df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NJ1+str(iS), DEP_Comp1,Usage,Vb,0]
                if NIV_Comp1==CL2 and CL_Comp1 in [2,3,4,8,9,13,17]:
                    Vb=Vb2/math.sqrt(3)
                    df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, NJ2+str(iS), DEP_Comp1,Usage,Vb,0]
                df_CompCnxNode = df_CompCnxNode.drop(df_CompCnxNode[(df_CompCnxNode.id_COP2 == iS)& (df_CompCnxNode.id_COP1 == Comp1)].index).reset_index(drop=True)
   
    df_CompCnxNode.rename(columns = {'id_COP2':'idNDE_COP2'}, inplace = True)   
        # df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, 'N_TrL_'+str(iS), DEP_iS,Usage,Vb,0]
        #  df_CompCnxNode.loc[len(df_CompCnxNode.index)]= [Node_id, 'N_TrM_'+str(iS), DEP_iS,Usage,Vb,0]
        #######################

    #print(df_CompCnxNode)
    df_CompCnxNode=df_CompCnxNode[df_CompCnxNode['UsageBus']!=5]
    df_CompCnxNode.dropna(inplace=True)
    df_CompCnxNode=df_CompCnxNode.reset_index(drop=True)
    
    At={}
    Bt=[]
    flagTrBus=0
    for ip2 in range(0,len(df_CompCnxNode)) :
        NDE_Comp2=df_CompCnxNode.iloc[ip2]['idNDE_COP2']
        df_Comp2=df_Comp[df_Comp['idNDE_COP'].values ==NDE_Comp2 ] 
        indxCL=np.where(df_Comp2['id_COP'].isin(COMPlist_unique) )[0][0]
        CLcomp2=df_Comp2['idCCL_COP'].iloc[indxCL]
        df_CompCnxNode.iloc[ip2,5]=CLcomp2
        id_COP1_N=df_CompCnxNode.iloc[ip2]['idNDE_COP2']  #id_COP1_N=df_CompCnxNode.iloc[ip2]['id_COP2'].split('_')[2]
        if CLcomp2==10:
            Bt.append(id_COP1_N)
            At.update({id_COP1_N:[ip2,Bt.count(id_COP1_N)]})
    #print(df_CompCnxNode[160:])
    #print(At)
    #print(TrBusDirecConnection)
    #print(df_CompCnxNode)
    Ct=[]
    for iA in At:
        #print(At[iA][1])
        if At[iA][1]==1 and iA:   ### it means the trans is open from one side and it's better to be deleted
            Ct.append(At[iA][0])
    #print(Ct)
    df_CompCnxNode.drop(Ct, axis=0, inplace=True)
    df_CompCnxNode.drop_duplicates(inplace=True)
    df_CompCnxNode=df_CompCnxNode.reset_index(drop=True)
    #print(df_CompCnxNode)
   
            
   
    return(df_CompCnxNode,COMPlist_unique,AddedTerm,CLNode)    

TYPTR2_COLUMNS = [
    'FID(a:40)',
    'outserv(i)',
    'loc_name(s:40)',
    'fold_id(p)',
    'nt2ph(i)',
    'strn(r)',
    'frnom(r)',
    'utrn_h(r)',
    'utrn_l(r)',
    'uktr(r)',
    'pcutr(r)',
    'uk0tr(r)',
    'ur0tr(r)',
    'tr2cn_h(s)',
    'tr2cn_l(s)',
    'nt2ag(i)',
    'curmg(r)',
    'pfe(r)',
    'zx0hl_n(r)',
    'itapch(i)',
    'tap_side(i)',
    'dutap(r)',
    'phitr(r)',
    'nntap0(i)',
    'ntpmn(i)',
    'ntpmx(i)',
    'manuf(s)',
]


def Couplage(Couplage_string1):

    
   
    if Couplage_string1 is None or len(Couplage_string1)==0 or '-' in Couplage_string1 :
        A='D'
        B='YN'
        PS=5
    else:
        Couplage_string1=Couplage_string1.replace(' ','')
        Couplage_string1 = Couplage_string1.upper()
        PS=Couplage_string1[-1]
        if PS.isdigit():
            #n_string = Couplage_string1.find(PS)
            Couplage_string=Couplage_string1.replace(PS,' ')
        else:
            Couplage_string=Couplage_string1
            PS=5
            
        PS1=Couplage_string1[-2:]
        if PS1.isdigit():
           # n_string = Couplage_string.find(PS1)
            Couplage_string=Couplage_string1.replace(PS1,' ')
            PS=PS1
    
        
        S=Couplage_string
       # print(S)
        
        if len(S)>0 and S[0] in ['D','Y','Z']:
            if 'N' in S[0:2]:
                A=S[0:2]
                a=1
            elif S[0] in ['D','Y','Z']:
                A=S[0]
                a=0
        else:
            A='D'
            a=-1
            
        b=a+1
        
        if len(S)>b and S[b] in ['Y','Z','D']:
            if 'N' in S[b:b+2]:
                B=S[b:b+2]
                
            else:
                B=S[b:b+1]
        else:
            B='YN'
    return(A,B,PS)
    #C=A+B
    #print(A)
    #print(B)
    #print(PS)  

# Transformer type
TypTr2 = pd.DataFrame(columns=TYPTR2_COLUMNS)
id_Typ_TR=df_Trans2['idCOP_TRF'].values
#Type_Ln=ElmLne['typ_id(p)'].values
def indices(lst, item):
    return [i for i, x in enumerate(lst) if x == item]

def CLNIV(iS):
    CompCL=df_Comp .loc[df_Comp ['id_COP']==iS]['idCCL_COP'].values[0]
    CompNIV=df_Comp .loc[df_Comp ['id_COP']==iS]['idNIV_COP'].values[0] 
    ComDEP=df_Comp.loc[df_Comp ['id_COP']==iS]['idNDE_COP'].values[0]  
    return [CompCL,CompNIV,ComDEP]
ctt=0
for itr in id_Typ_TR:
    FID= 'Tran_'+str(itr)
    df_TR=df_Trans2.loc[df_Trans2['idCOP_TRF']==itr]
    loc_name=FID
    fold_idTr='2-w Transformer Types'
    nt2ph=3
    strn=(df_TR['puissance_TRF'].values[0])/1000
    frnom=50

    
    T_prim=df_Trans2[df_Trans2['idCOP_TRF'] ==itr]['tensionPrimaire_TRF'].values[0]/1000
    T_sec=df_Trans2[df_Trans2['idCOP_TRF'] ==itr]['tensionSecondaire_TRF'].values[0]/1000
    
    if CLNIV(itr)[1]==4:

        utrn_h=T_prim if T_prim>1 else 16.8
        utrn_l=T_sec if T_sec>0.1 else 0.42
        
    else:
        utrn_h=T_prim if T_prim>35 else 65
        utrn_l=T_sec if T_sec>1 else 16.8
    
    #utrn_h=16.8 if CLNIV(itr)[1]==4 else 65
    #utrn_l=0.42 if CLNIV(itr)[1]==4 else 16.8
    uktr=df_TR['uCC_TRF'].values[0]
    pcutr=df_TR['perteCuivre_TRF'].values[0]/1000
    uk0tr=uktr
    ur0tr=0
    ################
    Couplage_string=df_Trans2[df_Trans2['idCOP_TRF'] ==itr]['couplage_TRF'].values[0]
    [tr2cn_h,tr2cn_l,nt2ag]=Couplage(Couplage_string)
    #tr2cn_h='D'
    #tr2cn_l='YN'
    #nt2ag=5
    ################
    
   
    curmg=2
    pfe=df_TR['perteFer_TRF'].values[0]/1000
    zx0hl_n=0
    itapch=1
    tap_side=0
    ###########
    df_dutap=df_Trans2.loc[df_Trans2['idCOP_TRF']==itr].deltaUPosInserateur_TRF.values[0] 
    if math.isnan(df_dutap) or df_dutap==0 :
        dutap=2.4
    else:
        dutap=((100*df_dutap)/(utrn_h*1000))
        
    ################# 
    
    phitr=0
    ########################
    #  ntpmx=5
   
    df_ntpmx=df_Trans2.loc[df_Trans2['idCOP_TRF']==itr].nbPosInserateur_TRF.values[0] 
    if math.isnan(df_ntpmx):
        if CLNIV(itr)[1]==4:
            ntpmx=5
           
        else:
            ntpmx=11
            
    else:
        ntpmx=df_ntpmx
        
    #######
    #nntap0=3
    Tap_0=ntpmx
    
    
    Tap_0=Tap_0 if Tap_0%2==1 else Tap_0+1
    nntap0=(Tap_0+1)/2
    #df_ntpmx=df_Trans2.loc[df_Trans2['idCOP_TRF']==itr].nbPosInserateur_TRF.values[0] 
    #if math.isnan(df_ntpmx):
        #if CLNIV(itr)[1]==4:
            # ntpmx=5
        # else:
          #   ntpmx=11
    # else:
      #  ntpmx=df_ntpmx
    
    ##
    ntpmn=1
    
    
    ###################
    manuf=' '
    TransTypes=[FID,'C',loc_name, fold_idTr,nt2ph,strn,frnom,utrn_h,utrn_l,uktr,pcutr,uk0tr,ur0tr,tr2cn_h,tr2cn_l,nt2ag,curmg,pfe,zx0hl_n,itapch,tap_side,dutap,phitr,nntap0,ntpmn,ntpmx,manuf]
    TypTr2.loc[ctt]=TransTypes
    ctt+=1
#DF_Types.append(TypTr2)
#ameDF_Types.append('TypTr2')

def StationCTCI(Node_id): 
    sta_pairs = []
    external_added = False
    [df_CompCnxNode,COMPlist_unique,AddedTerm,CLNode]=StationPreProc(Node_id)

    if CLNode==1:
        
        NT1='N_TrL_'
        NT2='N_TrM_'
        NJ1='N_JbL_'
        NJ2='N_JbM_'
        NS1='N_Fus_'
        NS2='N_SWM_'
    if CLNode in [3,5]:
        NT1='N_TrM_'
        NT2='N_TrH_'
        NJ1='N_JbM_'
        NJ2='N_JbH_'
        NS1='N_SWM_'
        NS2='N_SWH_'
    if CLNode==1:
        NT='L' 
    elif CLNode==3:
        NT='M'  
        
    df1 = df_NodCnx[df_NodCnx['id_NOD'].values ==Node_id] 
    fold_idN=df1['code_NOD'].values[0]
    idNODE=Node_id 
    df_CopX1=list(set(df_CompCnxNode['id_COP1']))
    #print(df_CompCnxNode)
    All_Comp=[]
    TransfoInSub=[]
    xi=0
    for i in df_CopX1:
        CompCnxF=df_CompCnxNode[df_CompCnxNode ['id_COP1']==i]
        Usage=CompCnxF['UsageBus'].values[0]
        Vb=CompCnxF['Voltage'].values[0]
        FID=CompCnxF['id_COP1'].values[0]
        #print(df_CopX1)
        for j in range(0, len(CompCnxF)):
            FID='Cub_'+str(i[2:])+'_'+str(j)
            CUB='Cub_'+str(j)
            fold_id=i
            NDE_comp2=CompCnxF['idNDE_COP2'].values[j]
            Busid=All_Comp.count(NDE_comp2) 
            #############
            if Busid>1:
                continue
            #############
                
            All_Comp.append(NDE_comp2)
            CLcomp2=CompCnxF['CL_COP2'].values[j]
           
            if CLcomp2==10:
                #print(str(i))
                object='Tr_'+str(NDE_comp2)
                Busid=1 if NT in str(i) else 0
                #print(Busid)
            #elif i in AddedTerm:
            elif CLcomp2 in [2,3,4,8,9,13,17,21]:
                object='SW_'+str(NDE_comp2)   ### the fuses or the switches at the input or output of the substation
            #else:
                #object='SW_'+str(NDE_comp2)    ### the internal  fuses or  switches   
             
            sta_pairs.append((fold_id, object))
            ################### EXTERNAL Network
            if 'N_JbH' in i and (j==len(CompCnxF)-1 and not external_added):
                df_SC=df_InfBus.loc[df_InfBus['idNOD_COP']==Node_id]['ICCTri_MBA'].dropna().tolist()
                if df_SC:
                    external_added = True
                    FID_ext='EXT'+'_'+str(Node_id)+'_'+str(xi)
                    MinSSC=min(df_SC)*math.sqrt(3)*65
                    MaxSSC=max(df_SC)*math.sqrt(3)*65
                    xi+=1
                    objectEX=FID_ext
                    FID_sta='Cub_'+str(i[2:])+'_'+str(len(CompCnxF))
                    CUB='Cub_'+str(len(CompCnxF))
                    fold_id=i
                    sta_pairs.append((fold_id, objectEX))
                
            ###################
            #print(StaCubic)
            if CLcomp2 in [2,3,4,8,9,13,17,21]:
                dfcom2 = df_Comp[df_Comp['idNDE_COP'].values ==NDE_comp2] 
                on_off=dfcom2.etatFlux_COP.values[0]
                if on_off==2:
                    on_off=0
                #print(ElmCoup)
            
            
            if CLcomp2 in [10] and object not in TransfoInSub: ##and Busid==1:  ## Busid==1 means that just consider the first Transformer of two duplicated ones
                #itr=int(i[6:])
                #if CLNIV(itr)[0]==10:

                    FID=object
                    loc_name=FID
                    #TYPE_id=df_Trans2[df_Trans2['idCOP_TRF'] ==512] ['idTTY_TRF'].values[0]
                    #comp2=df_Comp .loc[df_Comp ['idNDE_COP']==NDE_comp2]['id_COP'].values[0]
                    df_Comp2=df_Comp .loc[df_Comp ['idNDE_COP']==NDE_comp2]
                    indxCL=np.where(df_Comp2['id_COP'].isin(COMPlist_unique) )[0][0]
                    comp2=df_Comp2['id_COP'].iloc[indxCL]
                    TypeTr='Tran_'+str(comp2)  #str(TYPE_id)
                    ########################
                    
                    #TapPosition=3
                    df_TapPosition1=df_Trans2.loc[df_Trans2['idCOP_TRF']==comp2].posInserateur_TRF.values

                   # print(df_Trans2.loc[df_Trans2['idCOP_TRF']==comp2])
                   # print(comp2)
                    ##############
                    df_ntpmx=df_Trans2.loc[df_Trans2['idCOP_TRF']==comp2].nbPosInserateur_TRF.values
                    if math.isnan(df_ntpmx):
                        if CLNIV(comp2)[1]==4:
                            ntpmx=5
                           
                        else:
                            ntpmx=11
                            
                    else:
                        ntpmx=df_ntpmx
                    ##############3
                    if len(df_TapPosition1)==1:
                        df_TapPosition=df_TapPosition1[0]
                        #print(df_TapPosition)
                        if math.isnan(df_TapPosition) or df_TapPosition==0:
                            
                            if CLNIV(comp2)[1]==4:
                                if ntpmx>3:
                                    TapPosition=3
                                else:
                                    TapPosition=1
                            else:
                                if ntpmx>6:
                                    TapPosition=6
                                else:
                                    TapPosition=1
                        else:
                            TapPosition=df_TapPosition
                    else:
                        TapPosition=1
                    #################### Tap Inverse in Power Factory
                    """ ntpmxx=int(TypTr2.loc[TypTr2['FID(a:40)']==TypeTr]['ntpmx(i)'].values[0])
                    ntpminn=int(TypTr2.loc[TypTr2['FID(a:40)']==TypeTr]['ntpmn(i)'].values[0])
                    TapPositionInv=list(range(ntpmxx, ntpminn-1,-1))[int(TapPosition)-1] """
        
                    ######################
                    TransfoInSub.append(object)

    if not sta_pairs:
        return pd.DataFrame(columns=['From', 'To', 'Object', 'On\Off state', 'R(p.u)', 'X(p.u)', 'Rated power (kVA)', 'From: voltage (kV)', 'To: voltage (kV)'])

    df = pd.DataFrame(sta_pairs, columns=['fold_id', 'obj_id'])
    grouped = df.groupby("obj_id")["fold_id"].apply(list).reset_index()
    #print(grouped)
    
    # Split into two columns if multiple fold_id(p) exist
    grouped["fold_id_1"] = grouped["fold_id"].apply(lambda x: x[0] if len(x) > 0 else None)
    grouped["fold_id_2"] = grouped["fold_id"].apply(lambda x: x[1] if len(x) > 1 else None)
    grouped["common_obj_id"] = grouped["obj_id"]
    
    # Select relevant columns
    resultM = grouped[["fold_id_1", "fold_id_2", "common_obj_id"]]
    FromTo = resultM.dropna().reset_index()
    #print(FromTo)
###############
    def rearrange_folds(row):
        fold_1, fold_2 = row["fold_id_1"], row["fold_id_2"]
        
        # Ensure "N_SWM" in fold_id_1 and "N_Fus" in fold_id_2
        if (NS1 in fold_1 or NS2 in fold_2 or (NT1 in fold_1 and NT2 in fold_2)or (NJ2 in fold_2 and NT2 in fold_1) or 
        (NJ1 in fold_1 and NT1 in fold_2)):
            fold_1, fold_2 = fold_2, fold_1  # Swap them
        return pd.Series([fold_1, fold_2])

# Apply function to modify DataFrame
    FromTo[["fold_id_1", "fold_id_2"]] = FromTo.apply(rearrange_folds, axis=1)  # applies for each row of FromTo
    #####
    #df = df.drop(columns=['index'])  # 
    del FromTo['index']
    FromTo.columns = ['From', 'To','Object']  # 
    #return(ElmTerm,StaCubic,ElmTr2,ElmCoup,ElmXnet)   'Length(m)':
    # 'R(Ohm/km)':[], 'X(Ohm/km)':[], 'Ampacity (A)':[], 'PLmax(kW)':[], 
                                #  'QLmax(kVar)':[], 'Pg(kW)':[], 'Section(mm2)':[], 'Cu/Al':[]
    def RX_Trans(SString):
        NDE_comp2 = int(float(SString.split('_')[1]))
        #print(NDE_comp2)
        df_Comp2 = df_Comp.loc[(df_Comp['idNDE_COP'] == NDE_comp2) & (df_Comp['idCCL_COP'] == 10)]
        Tr_id_COP=df_Comp2['id_COP'].values[0]
        #print(Tr_id_COP)
        Type_Tr='Tran_'+str(Tr_id_COP)
        Type_Tr2=TypTr2.loc[(TypTr2['FID(a:40)'] == Type_Tr)]
        Sbase=(Type_Tr2['strn(r)'].values[0])*1000   # KVA
        Vbase=Type_Tr2['utrn_h(r)'].values[0]   # kV
        Ploss_cu=Type_Tr2['pcutr(r)'].values[0]  # kW
        Ploss_cu=0 if np.isnan(Ploss_cu) else Ploss_cu
        UK_percent=Type_Tr2['uktr(r)'].values[0]  # %
        Zsc=UK_percent/100
        Rsc=(Ploss_cu/Sbase)           # in pu.
        Xsc=(math.sqrt(Zsc**2-Rsc**2))
        return(Rsc,Xsc,Sbase)

    def SwitchState(SW):
        SwNdeID= IDSW=float((SW)[3: ])
        dfcom2 = df_Comp[df_Comp['idNDE_COP'].values ==SwNdeID] 
        on_off=dfcom2.etatFlux_COP.values[0]
        if on_off==2:
            on_off=0
        return(on_off)
    
       
    FromTo['On\\Off state'] = FromTo['Object'].apply(lambda x: SwitchState(x) if 'SW' in x else 1 )
    #FromTo['Length(m)'] =1 # FromTo['Object'].apply(lambda x: 1 if 'SW' in x else 0)
    FromTo['R(p.u)'] = FromTo['Object'].apply(lambda x: RX_Trans(x)[0] if 'Tr' in x else 0 )
    FromTo['X(p.u)'] = FromTo['Object'].apply(lambda x: RX_Trans(x)[1] if 'Tr' in x else 0 ) 
    FromTo['Rated power (kVA)'] = FromTo['Object'].apply(lambda x: RX_Trans(x)[2] if 'Tr' in x else 0 )
    FromTo['From: voltage (kV)'] = FromTo['From'].apply(lambda x: 0.4 if ('L' in x or 'Fus' in x) else (16 if 'M' in x else 65))
    FromTo['To: voltage (kV)'] = FromTo['To'].apply(lambda x: 0.4 if ('L' in x or 'Fus' in x) else (16 if 'M' in x else 65))

    #FromTo['Ampacity (A)'] = 2000
    #FromTo['PLmax(kW)'] = 0
    #FromTo['QLmax(kVar)'] = 0
    #FromTo['Pg(kW)'] = 0
    #FromTo['Section(mm2)'] = 500
    #FromTo['Cu/Al'] = 'Cu' 
       
    
    return FromTo 
#######



def Station_R(NODES):
    StationCon_LIS=[ ]
    Nodes=[]
    for idnode in NODES:
        if len(df_NodCnx.loc[df_NodCnx['id_NOD']==idnode])==0:
            continue
        print(idnode)
        station_df = StationCTCI(idnode)
        StationCon_LIS.append(station_df)
        Nodes.append(idnode)
        
    return(StationCon_LIS, Nodes)

def Next_Node_id(Node_id,branch,df):
    df2= df[df['id_BRA']==branch] 
    # df2 = df2.drop(df2[pd.notnull(df2["idNDE_COP"])].index)
    df2 = df2.drop(df2[(df2.id_NOD == Node_id)].index)  
    #Next_Node=[df2['id_NOD'].iloc[0]]   # contains a list [the fierts row is extracted]
    Next_Node=df2['id_NOD'].values
    if len(Next_Node)==0:
        return 'Nothing'

    #     return []
    else:       
        return Next_Node[0] #(df2.iloc[0,1])   ## [0] to give the name in a string format, not a List

def Node_Branches(Node_id,df):
    #df2= df[df['id_NOD']==Node_id] 
    #Branches=set(df2['id_BRA'].values)
    ####################
    df2= df[df['id_NOD']==Node_id] 
    Branch=[]
    BRANCH=list(df2['id_BRA'].values)
    for BRA in BRANCH:  #
        df10=df.loc[df['id_NOD']==Node_id].loc[df['id_BRA']==BRA] 
        Nod_Class=df10.idNCL_NOD.values[0] 
        FuseCoutState=df10.etatFlux_COP.values[0] 
        if (Nod_Class==4 or Nod_Class==6 or Nod_Class==7)  and FuseCoutState==0:   # (class 4: Armoir; class 6: Boite de distribution)
        
            continue
        else:
            Branch.append(BRA)
    Branches=set(Branch)  
    ####################
    return(Branches)
    ##############

def CTMT_Table2(idnode,ID_DEPART):     
#for idnode in [35]:
    M_Node = df_NodCnx[df_NodCnx['id_NOD'] == idnode]['code_NOD'].values[0]
    #rows, cols = (len(ID_DEPART), 1)
    DF_LIST=[[] for _ in range(len(ID_DEPART))] 
    #print(DF_LIST)
    #[ElmTerm_S,StaCubic_S,ElmTr2_S,ElmCoup_S, ElmXnet_S]=StationCTCI(idnode)
    ID_DEPART_idBR=[]
    All_Branch=[]   # to prevent the loops in the searches
    All_Loads=[]    # # to prevent the repetation of loads in the loops
    All_Gens=[]    # # to prevent the repetation of loads in the loops
    print(ID_DEPART)
    iSh=0
    iDL=0
     #MNodeXY={}
    # MNodeXY95={}
    DEPART_in_Loop=[]
    for ID_depart in ID_DEPART: # [3586.0, 3585.0]: # ID_DEPART:# [3548]: #ID_DEPART: # [3548]:  #ID_DEPART: #[3548]: #ID_DEPART:
            loop_flag=0
            loop_flag_out=0
            df1 = df_NodCnx[df_NodCnx['idNDE_COP'] == ID_depart] 
            Node='Fus'+'_'+str(ID_depart)
            #*****  To recognize two parallel feeders derived from a single ID_depart
            ID_DEPART_idBR.append(ID_depart)
            #print(ID_DEPART_idBR)
            Count_depart=ID_DEPART_idBR.count(ID_depart)-1
            #print(Count_depart)
            #****
            #print(Node)
            branch=(df1['id_BRA'].values)[Count_depart] #
            #print(branch)
            Node1=(df1['id_NOD'].values)[0]# 
            #print(Node1)
            Next=Next_Node_id(Node1,branch,df_NodCnx)
            #print(Next)
            if Next=='Nothing': #len([Next])==0:
                DF_LIST.pop()
                #print(DF_LIST)
                continue
            #################### there is a special case, feeder from substation connects to a fuse box with open fuse!
            df10=df_NodCnx.loc[df_NodCnx['id_NOD']==Next].loc[df_NodCnx['id_BRA']==branch]     # # (class 4: Armoir; class 6: Boite de distribution)
            #print(df10)
            Nod_Class=df10.idNCL_NOD.values[0] 
            FuseCoutState=df10.etatFlux_COP.values[0] 
            if (Nod_Class==4 or Nod_Class==6 or Nod_Class==1 or Nod_Class==7)  and FuseCoutState==0:
                DF_LIST.pop()
                continue
            else:
                M={Node:{branch}}
                Mcx={branch:[Node, Next]} 

            #################          
            #print(Next)
            
            M.update({Next:Node_Branches(Next,df_NodCnx)})
    
            #print(M)
    
            Mcx={branch:[Node, Next]} 
            #print(Mcx)
            j=0
    
            Mn=M
            Mcx1=Mcx
            print(ID_depart)
            while j!=len(M)-1:
    
        #print(len(M)-1)
        #print(j)
                #print(M)
        
                j+=1
            
           
                for k in range(0,j):
                    P=M
                    dd=list(P.keys())
                    
                    for n in  ((P.get(dd[j]).difference(P.get(dd[k]))) if P.get(dd[j]).intersection(P.get(dd[k]))!=set() else set()):            
                        #################
                        df10=df_NodCnx.loc[df_NodCnx['id_NOD']==dd[j]].loc[df_NodCnx['id_BRA']==n]     #
                        Nod_Class=df10.idNCL_NOD.values[0] 
                        FuseCoutState=df10.etatFlux_COP.values[0] 
                        if (Nod_Class==4 or Nod_Class==6 or Nod_Class==7)  and FuseCoutState==0:   # (class 4: Armoir; class 6: Boite de distribution)
                            continue
                        #############                   
                      
                        Next=Next_Node_id(dd[j],n,df_NodCnx)  
                        #print(n)
                        #print(Next)
                        if Next=='Nothing': #len([Next])==0:
                            continue
            
                        ####################
                        #print(Next)
                        #print(n)
                        df10=df_NodCnx.loc[df_NodCnx['id_NOD']==Next].loc[df_NodCnx['id_BRA']==n]     # # (class 4: Armoir; class 6: Boite de distribution)
                        Nod_Class=df10.idNCL_NOD.values[0] 
                        FuseCoutState=df10.etatFlux_COP.values[0] 
                        if (Nod_Class==4 or Nod_Class==6 or Nod_Class==7)  and FuseCoutState==0:           ### when fuse is Open, we stop the tracking the route
                            continue
            
                        #################
                        #M.update({Conx.get(n).get(dd[j]):S.get(Conx.get(n).get(dd[j]))})
                        #print(n)
                        #print(All_Branch)
                        if n in All_Branch:
                            continue
                        else:
                            M.update({Next:Node_Branches(Next,df_NodCnx)})
                            Mcx.update({n:[dd[j], Next]})
                        
                            
                        #*********** This part is added to distiguidh when a node is going to another station and prevent the loop            
                        #print(Next)
                        df10=df_NodCnx.loc[df_NodCnx['id_NOD']==Next].loc[df_NodCnx['id_BRA']==n]  # 
                        #print(df10)  
                        #df50=(df10.idNDE_COP.values) # it checks if this new node is a depart(feeder) in another post or not
                        #Cond= pd.isna(df50)[0]
                        Nod_Class=df10.idNCL_NOD.values[0]  # the node classes : class 1: Station CTMT
                        if   Nod_Class==1:  #not Cond and
                            if df10.id_NOD.values[0]==df1.id_NOD.values[0]:
                                M.popitem()
                                Mcx.popitem()
                            else:
                                New_Name='Fus'+'_'+str((df10.idNDE_COP.values[0]))
                                M.popitem()
                                M.update({New_Name:{n}})                               
                                Mcx[n][1]=New_Name
                        
            All_Branch.extend(list(Mcx.keys()))
            #print(All_Branch)
            #print(Mcx)   
            #print(M)
        # All_Branch.extend(list(Mcx.keys()))
        #print(Mcx)
            for isw in M.keys():
            
                if str(isw)[0:3]=='Fus':
            
                    IDSW=float((isw)[4: ])
                   
                    df1 = df_NodCnx[df_NodCnx['idNDE_COP'] == IDSW]
                    fold_id=df1['code_NOD'].values[0] 
                   #FID='SW'+'_'+str(ID_depart) if IDSW==ID_depart else 'SW'+'_'+str(IDSW)
                   #loc_name=FID
                 
                    on_off=df1.etatFlux_COP.values[0]
            
                    if on_off==1 and IDSW!=ID_depart:
                        loop_flag=1
                        ID_depart_loop=IDSW
                        Node_in_loop=(df1['id_NOD'].values)[0]# 
                        Loop_Node = df1['code_NOD'].values[0]
                        print (f"LOOP WARNING: the feeder id_NDE={ID_depart} of {M_Node} with the feeder id_NDE={ID_depart_loop} of {Loop_Node}")
                        DEPART_in_Loop.append(ID_depart_loop)
                        loop_flag=0
            
            id_BRA_CAB=df_Cable['id_BRA'].values
            id_CAT_CAB=df_CableType['id_CAT'].values
            
            id_BRA_OHL=df_OHL['id_BRA'].values
            id_CAT_OHL=df_OHLType['id_LTY'].values
            kr=0
            iSh=0
            df_Research=pd.DataFrame({'From':[ ], 'To':[ ], 'Line':[], 'Length(m)':[], 'R(Ohm/km)':[], 'X(Ohm/km)':[], 'Ampacity (A)':[], 'PLmax(kW)':[], 
                                      'QLmax(kVar)':[], 'Pg(kW)':[], 'Section(mm2)':[], 'Cu/Al':[], 'Cable/Line':[]})
            for ir in list(Mcx.keys()):   # it justs considers the keys
                
                if str(Mcx[ir][1])[0:3]=='Fus':
                    continue
               # if str(Mcx[ir][0])[0:3]=='Fus':
                    
                    # Slack=10000000000
                   # RMcx=Mcx[ir][0]
                    #toBus=int(float(RMcx[4:])*1000000)
                    ### 2025
                    # DF=[Slack, toBus,0, 0, 0, 0, 1000, 0, 0, 0,0,'Cu']
                    #df_Research.loc[kr]=DF
                #    kr+=1
                    
            
                
                id_BCL=df_NodCnx.loc[df_NodCnx['id_BRA']==ir]['idBCL_BRA'].values[0]
                if id_BCL==1: #(CABLE)
                         #indx = id_BRAn.index(cb_id)
                    #print(cb_id)
                    indx = np.where(id_BRA_CAB == ir)
                
                    if np.shape(indx[0])[0]==0:
                        IDX=2
                    else:   
                        IDX=indx[0][0]
            
                    dline=df_Cable['longueur_BRA'].iloc[IDX]
                    #print(dline)
                    Typ_CAT=df_Cable['id_CAT'].iloc[IDX]
                    indx1 = np.where(id_CAT_CAB == Typ_CAT)
                    IDX1=indx1[0][0]
                    Rline=df_CableType['resLineique_CAT'].iloc[IDX1]
                    rline=0 if pd.isna(Rline) else float(Rline)                   # resistance in ohm per km
                    Xline=df_CableType['indLineique_CAT'].iloc[IDX1]
                    xline=0 if pd.isna(Xline) else float(Xline)
                    AdmCurrent=df_CableType['courantAdmissible_CAT'].iloc[IDX1]
                    AdmCurrent=0 if pd.isna(AdmCurrent) else float(AdmCurrent)
                    Section=df_CableType['section_CAT'].iloc[IDX1]
                    Section=0 if pd.isna(Section) else float(Section)
                    mterail=df_CableType['materiel_CAT'].iloc[IDX1]
                    mterail=str(mterail) if not pd.isna(mterail) else ''
                    LineType='Cable' 
                    
                   # Dict[item]
                 ########################
                if id_BCL==2: #(OHL)
                         #indx = id_BRAn.index(cb_id)
                    #print(cb_id)
                    indx = np.where(id_BRA_OHL == ir)
                
                    if np.shape(indx[0])[0]==0:
                        IDX=52
                    else:   
                        IDX=indx[0][0]
            
                    dline=df_OHL['longueur_BRA'].iloc[IDX]
                    #print(dline)
                    Typ_CAT=df_OHL['idLTY_LIG'].iloc[IDX]
                    indx1 = np.where(id_CAT_OHL == Typ_CAT)
                    IDX1=indx1[0][0]
                    Rline=df_OHLType['resLineique_LTY'].iloc[IDX1]
                    rline=0 if pd.isna(Rline) else float(Rline)                   # resistance in ohm per km
                    Xline=df_OHLType['indLineique_LTY'].iloc[IDX1]
                    xline=0 if pd.isna(Xline) else float(Xline)
                    AdmCurrent=df_OHLType['courantAdmissible_LTY'].iloc[IDX1]
                    AdmCurrent=0 if pd.isna(AdmCurrent) else float(AdmCurrent)
                    Section=df_OHLType['section_LTY'].iloc[IDX1]
                    Section=0 if pd.isna(Section) else float(Section)
                    mterail=df_OHLType['materiel_LTY'].iloc[IDX1]
                    mterail=str(mterail) if not pd.isna(mterail) else ''
                    LineType='Line' 
                   # Dict[item]
                if Mcx[ir][1] in idNOD_COF_Load:           # Loads                
                   
                     indx2 = np.where(idNOD_COF_Load == Mcx[ir][1])
                     IDX2=indx2[0][0]
                     courantFinance=df_Coffret_Load['courantFinance_COF'].iloc[IDX2]
                     courantConsigne=df_Coffret_Load['courantConsigne_COF'].iloc[IDX2]
                     Fuse_Current=courantConsigne if (math.isnan(courantFinance) or courantFinance==0) else courantFinance
                     coslini=0.9
                     simFactor=1
                     plini=math.sqrt(3)*0.4*Fuse_Current*coslini*simFactor
                     #slini=math.sqrt(3)*0.4*Fuse_Current
                     qlini=plini*math.tan(math.acos(coslini))
                
                    ### load type formation (HA formation for the Nodes)
                else:
                    plini=0
                    qlini=0
                
                if Mcx[ir][1] in idNOD_COF_Gen:           # Gen                
                    
                     indx3 = np.where(idNOD_COF_Gen == Mcx[ir][1])
                    # IDX3=indx3[0][0]
                     Rated_App_Power=df_Coffret_Gen['puissanceMax_EPR'].iloc[indx3].sum()
                     simFactorG=1
                     sgn=Rated_App_Power*simFactorG
                else:
                    sgn=0
               
                FromBus='N_'+str(Mcx[ir][0])
                ToBus='N_'+str(Mcx[ir][1])
                ## 2025
               # if str(Mcx[ir][0])[0:3]=='Fus':
                    # Slack=10000000000
                    # RMcx=Mcx[ir][0]
                   #  FromBus=int(float(RMcx[4:])*1000000)
                    
               
                DF=[FromBus, ToBus, ir, dline, rline, xline, AdmCurrent, plini, qlini, sgn, Section, mterail, LineType]
                #print(Section)    
                df_Research.loc[kr]=DF
                kr+=1
            #
            DF_LIST[iDL]=df_Research
            iDL+=1
           # DF_LIST.append(df_Research)
           # iDL+=1
            #print(iDL)
            #print(df_Research)
            
            
        
    #print(DF_LIST)    
    DF_LIST_Con_Node=[]
    
    if DF_LIST!=[]:  
        Flag_Empty_DF_LIST=0
        dfCon=pd.concat(DF_LIST , ignore_index=True)
        dfCon.drop_duplicates(inplace=True)
        dfCon=dfCon.reset_index(drop=True)
        DF_LIST_Con_Node.append(dfCon)
        DF_NODE=DF_LIST_Con_Node
    else:
        Flag_Empty_DF_LIST=1
        DF_NODE='DF_NOTHING'
        
    return[DF_NODE, DEPART_in_Loop, Flag_Empty_DF_LIST]
    
    
        

#####################
def CIMT_Table2(idnode,LV_Nodes):

    df_ID_DEPART=df_NodCnx.loc[df_NodCnx['id_NOD']==idnode].loc[df_NodCnx['idNIV_COP']==2]   ### MT
    ID_DEPART= list(df_ID_DEPART.idNDE_COP.values)
   
    M_Node = df_NodCnx[df_NodCnx['id_NOD'] == idnode]['code_NOD'].values[0]
    
    #rows, cols = (len(ID_DEPART), 1)
    #DF_LIST=[[[] for i in range(cols)] for j in range(rows)]
    WO_LV_Nodes=[] ## like MV switches
    DF_LIST=[[] for _ in range(len(ID_DEPART))] 
    
    ID_DEPART_idBR=[]
    All_Branch=[]   # to prevent the loops in the searches
    
    
    print(ID_DEPART)
    iSh=0
    iDL=0
    
    DEPART_in_Loop=[]
    df_NodCnx_M=df_NodCnx.loc[df_NodCnx['idNIV_COP']==2] 
    M={}
    Mcx={}
    for ID_depart in ID_DEPART: # [3586.0, 3585.0]: # ID_DEPART:# [3548]: #ID_DEPART: # [3548]:  #ID_DEPART: #[3548]: #ID_DEPART:
        if ID_depart in DEPART_in_Loop:
            DF_LIST.pop()
            continue
        loop_flag=0
        loop_flag_out=0
        df1 = df_NodCnx[df_NodCnx['idNDE_COP'] == ID_depart] 
        Node='SWM_'+str(ID_depart)
        print(ID_depart)
        #*****
        ID_DEPART_idBR.append(ID_depart)
        #print(ID_DEPART_idBR)
        Count_depart=ID_DEPART_idBR.count(ID_depart)-1
        #print(Count_depart)
        #****
         #print(Node)
        branch=(df1['id_BRA'].values)[Count_depart] #
        #print(branch)
        Node1=(df1['id_NOD'].values)[0]# 
        #print(Node1)
        Next=Next_Node_id(Node1,branch,df_NodCnx_M)
        #print(Next)
        if Next=='Nothing': #len([Next])==0:
            DF_LIST.pop()
            #print(DF_LIST)
            continue
         #################### there is a special case, feeder from substation connects to a fuse box with open fuse!
        df10=df_NodCnx_M.loc[df_NodCnx_M['id_NOD']==Next].loc[df_NodCnx_M['id_BRA']==branch].loc[df_NodCnx_M['idNIV_COP']==2]     # # (class 4: Armoir; class 6: Boite de distribution)
        #print(df10)
        Nod_Class=df10.idNCL_NOD.values[0] 
        #print(Nod_Class)
        FuseCoutState=df10.etatFlux_COP.values[0] 
        if FuseCoutState==2:
           FuseCoutState=0
        if (Nod_Class==3 or Nod_Class==1 )  and FuseCoutState==0:
            DF_LIST.pop()
            continue
        else:
            M={Node:{branch}}
            NextNode='SWM_'+str((df10.idNDE_COP.values[0])) if Nod_Class==1 else Next
            Mcx={branch:[Node, NextNode]} 
    
        ################# 
        M.update({Next:Node_Branches(Next,df_NodCnx_M)})
    
        j=0
    
        Mn=M
        Mcx1=Mcx
        #print(ID_depart)
        M_o={}
        Mcx_o={}
        while j!=len(M)-1:
    
            j+=1
        
       
            for k in range(0,j):
                P=M
                dd=list(P.keys())
                #print(dd)
                
                for n in  ((P.get(dd[j]).difference(P.get(dd[k]))) if P.get(dd[j]).intersection(P.get(dd[k]))!=set() else set()):
    
        
                    df10=df_NodCnx_M.loc[df_NodCnx_M['id_NOD']==dd[j]].loc[df_NodCnx_M['id_BRA']==n].loc[df_NodCnx_M['idNIV_COP']==2]  
                    Nod_Class=df10.idNCL_NOD.values[0] 
                    PresentNode='SWM_'+str((df10.idNDE_COP.values[0])) if Nod_Class in [1,5] else dd[j]
                   # if Nod_Class in [5,16]:
                      #  PresentNode='SWM_'+str((df10.idNDE_COP.values[0]))
                      #  Mcx.update({'SW_'+str((df10.id_NOD.values[0])):[NextNode,PresentNode]})
                        
                    
                    FuseCoutState=df10.etatFlux_COP.values[0]
                    if FuseCoutState==2:
                       FuseCoutState=0
                    #if Nod_Class==1  and FuseCoutState==0:   # (class 4: Armoir; class 6: Boite de distribution)
                    if Nod_Class in [1,5]  and FuseCoutState==0:   # (class 4: Armoir; class 6: Boite de distribution)
    
                        continue
                    #############                   
                  
                    Next=Next_Node_id(dd[j],n,df_NodCnx_M)  
                    #print(n)
                    #print(Next)
                    if Next=='Nothing': #len([Next])==0:
                        continue
        
                    ####################
                    #print(Next)
                    #print(n)
                    df10=df_NodCnx_M.loc[df_NodCnx_M['id_NOD']==Next].loc[df_NodCnx_M['id_BRA']==n].loc[df_NodCnx_M['idNIV_COP']==2]        # # (class 4: Armoir; class 6: Boite de distribution)
                    Nod_Class=df10.idNCL_NOD.values[0] 
                    
                    FuseCoutState=df10.etatFlux_COP.values[0] 
                    if FuseCoutState==2:
                       FuseCoutState=0
                    if Nod_Class==1   and FuseCoutState==0:           ### when next switch is open stops the tracking
                        M_o.update({Next:Node_Branches(Next,df_NodCnx_M)})
                        NextNode='SWM_'+str((df10.idNDE_COP.values[0])) if Nod_Class==1 else Next
                        Mcx_o.update({n:[PresentNode, NextNode]})
                        continue
    
                    if n in All_Branch:
                        continue
                    else:
                        M.update({Next:Node_Branches(Next,df_NodCnx_M)})
                        
                        #NextNode='SWM_'+str((df10.idNDE_COP.values[0])) if Nod_Class==1 else Next
                        NextNode=Next
                        #print(NextNode)
                       # if Nod_Class==1:
                         #   NextNode='SWM_'+str((df10.idNDE_COP.values[0]))
                          #  print('Hi')
                          #  print(NextNode)
                        if Nod_Class in [1,5,16]:
                            NextNode='SWM_'+str((df10.idNDE_COP.values[0]))
                            #print('Hi')
                            #print(NextNode)
                    
                            
                        #NextNode='SWM_'+str((df10.idNDE_COP.values[0])) if Nod_Class in [5,16] else Next 
                        #print([Next,Nod_Class,NextNode])  
                        Mcx.update({n:[PresentNode, NextNode]})
          
                    #print(Next)
                    df10=df_NodCnx_M.loc[df_NodCnx_M['id_NOD']==Next].loc[df_NodCnx_M['id_BRA']==n].loc[df_NodCnx_M['idNIV_COP']==2]     # 
                    Nod_Class=df10.idNCL_NOD.values[0]  # the node classes : class 1: Station CTMT
                    if   Nod_Class in [3] :  #not Cond and
                    #if df10.id_NOD.values[0]==df1.id_NOD.values[0]:
                       # M.popitem()
                       # Mcx.popitem()
                    #else:
                        New_Name='SWM_'+str((df10.idNDE_COP.values[0]))
                        M.popitem()
                        M.update({New_Name:{n}})                               
                        Mcx[n][1]=New_Name
                    
        All_Branch.extend(list(Mcx.keys()))
        #print(Mcx_o)
        Mcx.update(Mcx_o) 
        M.update(M_o)
        #print(M)
        Mcx.values()
        NodesInFeeder=[]
        for i in Mcx.values():
            if i[0] not in NodesInFeeder:
                NodesInFeeder.append(i[0]) 
            if i[1] not in NodesInFeeder:
                NodesInFeeder.append(i[1]) 
    
        #### the nodes that don't have LV parts like Switches, WO_LV_Nodes
        for it in NodesInFeeder:
                
                if str(it)[0:3]=='SWM':
              
                    df1 = df_NodCnx[df_NodCnx['idNDE_COP'].values ==float((it)[4: ])] 
                    
                    if len(df1)!=0:
                        if df1['id_NOD'].values[0] not in LV_Nodes:
                            WO_LV_Nodes.append(df1['id_NOD'].values[0])
                            
        ######################################################
        DF_list= list()
        NameDF= list()
        #print(Mcx)
        #print(Mcx)
        id_BRA_CAB=df_Cable['id_BRA'].values
        id_CAT_CAB=df_CableType['id_CAT'].values
        
        id_BRA_OHL=df_OHL['id_BRA'].values
        id_CAT_OHL=df_OHLType['id_LTY'].values
        kr=0
        iSh=0
        df_Research=pd.DataFrame({'From':[ ], 'To':[ ], 'Line':[], 'Length(m)':[], 'R(Ohm/km)':[], 'X(Ohm/km)':[], 'Ampacity (A)':[], 'PLmax(kW)':[], 
                                  'QLmax(kVar)':[], 'Pg(kW)':[], 'Section(mm2)':[], 'Cu/Al':[], 'Cable/Line':[] })
        for ir in list(Mcx.keys()):   # it justs considers the keys
            
            if str(Mcx[ir][1])[0:3]=='Fus':
                continue
        
            
            id_BCL=df_NodCnx.loc[df_NodCnx['id_BRA']==ir]['idBCL_BRA'].values[0]
            if id_BCL==1: #(CABLE)
                     #indx = id_BRAn.index(cb_id)
                #print(cb_id)
                indx = np.where(id_BRA_CAB == ir)
            
                if np.shape(indx[0])[0]==0:
                    IDX=2
                else:   
                    IDX=indx[0][0]
        
                dline=df_Cable['longueur_BRA'].iloc[IDX]
                #print(dline)
                Typ_CAT=df_Cable['id_CAT'].iloc[IDX]
                indx1 = np.where(id_CAT_CAB == Typ_CAT)
                IDX1=indx1[0][0]
                Rline=df_CableType['resLineique_CAT'].iloc[IDX1] 
                rline=0 if pd.isna(Rline) else float(Rline)                   # resistance in ohm per km
                Xline=df_CableType['indLineique_CAT'].iloc[IDX1] 
                xline=0 if pd.isna(Xline) else float(Xline)  
                AdmCurrent=df_CableType['courantAdmissible_CAT'].iloc[IDX1] 
                AdmCurrent=0 if pd.isna(AdmCurrent) else float(AdmCurrent)
                Section=df_CableType['section_CAT'].iloc[IDX1]
                Section=0 if pd.isna(Section) else float(Section)
                mterail=df_CableType['materiel_CAT'].iloc[IDX1]
                mterail=str(mterail) if not pd.isna(mterail) else ''
                LineType='Cable' 
               # Dict[item]
             ########################
            if id_BCL==2: #(OHL)
                     #indx = id_BRAn.index(cb_id)
                #print(cb_id)
                indx = np.where(id_BRA_OHL == ir)
            
                if np.shape(indx[0])[0]==0:
                    IDX=52
                else:   
                    IDX=indx[0][0]
        
                dline=df_OHL['longueur_BRA'].iloc[IDX]
                #print(dline)
                Typ_CAT=df_OHL['idLTY_LIG'].iloc[IDX]
                indx1 = np.where(id_CAT_OHL == Typ_CAT)
                IDX1=indx1[0][0]
                Rline=df_OHLType['resLineique_LTY'].iloc[IDX1] 
                rline=0 if pd.isna(Rline) else float(Rline)                   # resistance in ohm per km
                Xline=df_OHLType['indLineique_LTY'].iloc[IDX1] 
                xline=0 if pd.isna(Xline) else float(Xline)  
                AdmCurrent=df_OHLType['courantAdmissible_LTY'].iloc[IDX1] 
                AdmCurrent=0 if pd.isna(AdmCurrent) else float(AdmCurrent)
                Section=df_OHLType['section_LTY'].iloc[IDX1]
                Section=0 if pd.isna(Section) else float(Section)
                mterail=df_OHLType['materiel_LTY'].iloc[IDX1]
                mterail=str(mterail) if not pd.isna(mterail) else ''
                LineType='Line' 
               # Dict[item]
            if Mcx[ir][1] in idNOD_COF_Load:           # Loads                
               
                 indx2 = np.where(idNOD_COF_Load == Mcx[ir][1])
                 IDX2=indx2[0][0]
                 courantFinance=df_Coffret_Load['courantFinance_COF'].iloc[IDX2]
                 courantConsigne=df_Coffret_Load['courantConsigne_COF'].iloc[IDX2]
                 Fuse_Current=courantConsigne if (math.isnan(courantFinance) or courantFinance==0) else courantFinance
                 coslini=0.9
                 simFactor=1
                 plini=math.sqrt(3)*0.4*Fuse_Current*coslini*simFactor
                 #slini=math.sqrt(3)*0.4*Fuse_Current
                 qlini=plini*math.tan(math.acos(coslini))
            
                ### load type formation (HA formation for the Nodes)
            else:
                plini=0
                qlini=0
            
            if Mcx[ir][1] in idNOD_COF_Gen:           # Gen                
                
                 indx3 = np.where(idNOD_COF_Gen == Mcx[ir][1])
                 IDX3=indx3[0][0]
                 Rated_App_Power=df_Coffret_Gen['puissanceMax_EPR'].iloc[IDX3]
                 simFactorG=1
                 sgn=Rated_App_Power*simFactorG
            else:
                sgn=0
            FromBus='N_'+str(Mcx[ir][0])
            ToBus='N_'+str(Mcx[ir][1])
            ## 2025
           # if str(Mcx[ir][0])[0:3]=='Fus':
                # Slack=10000000000
                # RMcx=Mcx[ir][0]
               #  FromBus=int(float(RMcx[4:])*1000000)
                
           
            DF=[FromBus, ToBus, ir, dline, rline, xline, AdmCurrent, plini, qlini, sgn, Section, mterail, LineType]
            #print(Section)    
            df_Research.loc[kr]=DF
            kr+=1
        #
        #DF_LIST.append(df_Research)
        DF_LIST[iDL]=df_Research    
        iDL+=1

    ###
    DF_LIST_Con_Node=[]
    
    if DF_LIST!=[]:  
        Flag_Empty_DF_LIST=0
        dfCon=pd.concat(DF_LIST , ignore_index=True)
        dfCon.drop_duplicates(inplace=True)
        dfCon=dfCon.reset_index(drop=True)
        DF_LIST_Con_Node.append(dfCon)
        DF_NODE=DF_LIST_Con_Node
    else:
        Flag_Empty_DF_LIST=1
        DF_NODE='DF_NOTHING'



    
    #print(iDL)
    #print(DF_LIST)
    return[DF_NODE, WO_LV_Nodes] 

  
#####################
def CTMT_NETWORK_R(NODES):
    #NODES=[470]
    rows, cols = (len(NODES), 1)
    #DF_LIST_Net=[[[] for i in range(cols)] for j in range(rows)]
    DF_LIST_Net=[[] for _ in range(len(NODES))]
    StationCon_LIS=[ ]
    iDN=0
    DEPART_IN_LOOP=[]
    LV_Nodes=[]
    Common_in_LV_MV_Nodes=[]
    Nodes=[]
    for idnode in NODES:
    
        
        df_ID_DEPART=df_NodCnx.loc[df_NodCnx['id_NOD']==idnode].loc[df_NodCnx['idNIV_COP']==1]   ### BT
        ID_DEPART1= list(df_ID_DEPART.idNDE_COP.values)
        
        flagLP=0
        flagOp_Sw=0
        ID_DEPART=[]
        for ID_depart in  ID_DEPART1:
                df1 = df_NodCnx[df_NodCnx['idNDE_COP'] == ID_depart] #df1 = df.query('id_NOD==nde')   depart 84701 est en vide, fuse open: 5629
                if len(df1)==0:
                    print (f"There is no feeder, Node number: {idnode} feeder number: {ID_depart}")
                    #ID_DEPART.remove(ID_depart)
                    continue
                if df1.etatFlux_COP.values[0]==0:
                    flagOp_Sw=1
                    print (f"The fuse is open, Node number: {idnode}, feeder number:{ID_depart}")
                    #ID_DEPART.remove(ID_depart)
                    continue
                if ID_depart in DEPART_IN_LOOP:
                    print (f"The feeder id_NDE={ID_depart} at Node number: {idnode} has been mentioned that is in loop")
                    flagLP=1
                    #ID_DEPART.remove(ID_depart)
                    continue
                ID_DEPART.append(ID_depart)
        
           ######################################## To Specify and bypass totally isolated substations from LV network and MV network
        ConnectionTo_MV_Flag=1 
        if len(ID_DEPART)==0:  ## No connection to LV network
            ConnectionTo_MV_Flag=0
            df3 = df_NodCnx[df_NodCnx['id_NOD'] == idnode].id_BRA.values
            for i in df3:
                df4=df_NodCnx[df_NodCnx['id_BRA'] == i].etatFlux_COP.values
                if (df4[0]==1 and df4[1]==1):
                    ConnectionTo_MV_Flag=1 
        if ConnectionTo_MV_Flag==0:  ## No connection to MV network
            DF_LIST_Net.pop()
            continue
            ##############
        [DF_NODE, DEPART_in_Loop, Flag_Empty_DF_LIST]=CTMT_Table2(idnode,ID_DEPART) 
        #print(DEPART_in_Loop)
        #DEPART_IN_LOOP.extend(DEPART_in_Loop)
        
        #if DF_NODE !='DF_NOTHING':
            #LV_Nodes.append(idnode
        #print (f"Flag_Empty_DF_LIST: {Flag_Empty_DF_LIST} ")   
        if Flag_Empty_DF_LIST==1:
             
            if flagLP==1 or flagOp_Sw==1:
                CodeNode=df_NodCnx.loc[df_NodCnx['id_NOD']==idnode].code_NOD.values[0]
                Common_in_LV_MV_Nodes.append(CodeNode)#this MV node, once in its loop with anothe substation was considered 
                #as ElmTrfstat node. then we save to delete it in ElmTrfstat of netork
        else:
            LV_Nodes.append(idnode)

        if DF_NODE=='DF_NOTHING':
            DF_LIST_Net.pop()
            continue
    
        DF_LIST_Net[iDN]=DF_NODE
        iDN+=1
        Nodes.append(idnode)
    return[DF_LIST_Net, LV_Nodes,Nodes] 

def CIMT_NETWORK_R(NODES,LV_Nodes):
    #rows, cols = (len(NODES), 1)
    #DF_LIST_Net=[[[] for i in range(cols)] for j in range(rows)]
    rows, cols = (len(NODES), 1)
    #DF_LIST_Net=[[[] for i in range(cols)] for j in range(rows)]
    DF_LIST_Net=[[] for _ in range(len(NODES))]
    iDN=0
    DEPART_IN_LOOP=[]
    WO_LV_NODES=[]
    Nodes=[]
    for idnode in NODES:
        print(idnode)
        if len(df_NodCnx.loc[df_NodCnx['id_NOD']==idnode])==0:
            DF_LIST_Net.pop()
            continue
    
        
        if df_NodCnx.loc[df_NodCnx['id_NOD']==idnode].idNCL_NOD.values[0]==5:
            ID_DEPART=[]
        else: 
            df_ID_DEPART=df_NodCnx.loc[df_NodCnx['id_NOD']==idnode].loc[df_NodCnx['idNIV_COP']==2]   ### MT
            ID_DEPART1= list(df_ID_DEPART.idNDE_COP.values)
            #ID_DEPART1=[2895.0] #[102637.0, 102634.0] #[102621.0, 102622.0, 102630.0,102634.0]  #102632.0, 102637.0, 102634.0, 102627.0
            ID_DEPART=[]
            for ID_depart in  ID_DEPART1:
                
                    df1 = df_NodCnx[df_NodCnx['idNDE_COP'] == ID_depart] #df1 = df.query('id_NOD==nde')   depart 84701 est en vide, fuse open: 5629
                    if len(df1)==0:
                        print (f"There is no feeder, Node number: {idnode} feeder number: {ID_depart}")
                        #ID_DEPART.remove(ID_depart)
                        continue
                    if df1.etatFlux_COP.values[0]==0:
                        print (f"The fuse is open, Node number: {idnode}, feeder number:{ID_depart}")
                        #ID_DEPART.remove(ID_depart)
                        continue
                    if ID_depart in DEPART_IN_LOOP:
                        print (f"The feeder id_NDE={ID_depart} at Node number: {idnode} has been mentioned that is in loop")
                        #ID_DEPART.remove(ID_depart)
                        continue
                    ID_DEPART.append(ID_depart)
            #print(ID_DEPART)
            if len(ID_DEPART)==0:
                print (f"There is no feeder, Node number: {idnode}")
                DF_LIST_Net.pop()
                continue
            #print(ID_DEPART)
        #ID_DEPART = [66150]
        #[NAME_DF_NODE, DF_NODE,DEPART_in_Loop]=CIMT_NETWORK(idnode,ID_DEPART,LV_Nodes) 
        [DF_NODE, WO_LV_Nodes]= CIMT_Table2(idnode,LV_Nodes)
        #print(DF_NODE)
        #DEPART_IN_LOOP.extend(DEPART_in_Loop)
        
        
        
        if DF_NODE=='DF_NOTHING':
            DF_LIST_Net.pop()
            continue
        WO_LV_NODES.extend(WO_LV_Nodes)    
        DF_LIST_Net[iDN]=DF_NODE
        Nodes.append(idnode)
        iDN+=1
        #print(iDN)
    
    #if iDN==1:
        #DF_LIST_Con_Net=DF_LIST_Net
    #else:
   # DF_LIST_Con_Net=[]
   # if DF_LIST_Net!=[[[]]] and DF_LIST_Net!=[]:
      #  for iConN in range(0,len(DF_NODE)):
         #   dfConN=pd.concat([row[iConN] for row in DF_LIST_Net] , ignore_index=True)
          #  dfConN.drop_duplicates(inplace=True)
           # dfConN=dfConN.reset_index(drop=True)
          #  DF_LIST_Con_Net.append(dfConN)
    return(DF_LIST_Net,WO_LV_NODES,Nodes)    



import timeit
start = timeit.default_timer()

################   
NodesSierreToSion=[92709, 92515, 92707]
##############################
NODE_Sierre_MT=list(df_NODE_Sierre_MT['id_NOD'].values)
NODE_Sierre_HT=list(df_NODE_Sierre_HT['id_NOD'].values)
##############################
NODE_Sion_MT=list(df_NODE_Sion_MT['id_NOD'].values)
NODE_Sion_HT=list(df_NODE_Sion_HT['id_NOD'].values)
##############################
for it in NodesSierreToSion:
    NODE_Sierre_MT.remove(it)
    
#NODES_MT=NODE_Sierre_MT# len(NODE_Sierre)+1
NODE_Sion_MT.remove(2090)
NODE_Sion_MT.extend(NodesSierreToSion)
#######################################

if City=='Sion':
    NODES=NODE_Sion_MT
    HT_NODES=NODE_Sion_HT
elif City=='Sierre':
    NODES=NODE_Sierre_MT
    HT_NODES=NODE_Sierre_HT
else:
    print('Write City name correctly')


[DF_Net_LV, MV_LV_Nodes,NODES_MT_BT]=CTMT_NETWORK_R(NODES)
[DF_Net_MV, WO_LV_Nodes, NODES_HT_MT]=CIMT_NETWORK_R(HT_NODES,MV_LV_Nodes)   

#MVLV_Nodes.extend(WO_LV_Nodes)

[MV_LV_substations, MVLV_SubstationId]=Station_R(MV_LV_Nodes)
[MV_Stations, MV_StationsId]=Station_R(WO_LV_Nodes)
[HV_LV_substations, HV_LV_SubstationId]=Station_R(HT_NODES)


stop = timeit.default_timer()    
print('Time: ', stop - start) 

file_name_LV_Grid = '1_LV Grid_Sion.xlsx'
file_name_MV_Grid = '2_MV Grid_Sion.xlsx'
file_name_MV_LV_Substations = '3_MV-LV Substation_Sion.xlsx'   
file_name_MV_Stations = '4_MV Stations_Sion.xlsx'
file_name_HV_MV_Substations = '5_HV-MV Substations_Sion.xlsx'

# One per sheet
iSh=0
with pd.ExcelWriter(file_name_LV_Grid) as writer:
    # writing to the 'Employee' sheet
    for DF in DF_Net_LV:
        df_to_write = add_endpoint_coordinates(DF[0])
        df_to_write.to_excel(writer, sheet_name='LV_Grid_'+str(NODES_MT_BT[iSh]), index=False)
        iSh+=1
    print('DataFrames of LV_Grid is written to Excel File successfully.')
###################
iSh=0
with pd.ExcelWriter(file_name_MV_Grid) as writer:
    
    for DF in DF_Net_MV:
        df_to_write = add_endpoint_coordinates(DF[0])
        df_to_write.to_excel(writer, sheet_name='MV_Grid_'+str(NODES_HT_MT[iSh]), index=False)
        iSh+=1
    print('DataFrames of MV_Grid are written to Excel File successfully.')

###############################################
iSh=0
with pd.ExcelWriter(file_name_MV_LV_Substations) as writer:
    
    for DF in MV_LV_substations:
        df_to_write = add_endpoint_coordinates(DF)
        df_to_write.to_excel(writer, sheet_name='Substation_'+str(MVLV_SubstationId[iSh]), index=False)
        iSh+=1
    print('DataFrames of MV_LV_substations are written to Excel File successfully.')

####################
iSh=0

with pd.ExcelWriter(file_name_MV_Stations) as writer:
    
    for DF in MV_Stations:
        df_to_write = add_endpoint_coordinates(DF)
        df_to_write.to_excel(writer, sheet_name='MV_Station_'+str(MV_StationsId[iSh]), index=False)
        iSh+=1
    print('DataFrames of MV_Stations are written to Excel File successfully.')
#################
iSh=0
with pd.ExcelWriter(file_name_HV_MV_Substations) as writer:
    
    for DF in HV_LV_substations:
        df_to_write = add_endpoint_coordinates(DF)
        df_to_write.to_excel(writer, sheet_name='Substation_'+str(HV_LV_SubstationId[iSh]), index=False)
        iSh+=1
    print('DataFrames of HV_MV_Substations are written to Excel File successfully.')