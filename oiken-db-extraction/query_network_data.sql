SELECT DISTINCT
    n1.id_NOD AS From_id,
    n1.code_NOD AS [From],
    n2.id_NOD AS To_id,
    n2.code_NOD AS [To],
    b.id_BRA AS Line,
    b.longueur_BRA AS [Length(m)],
    CASE b.idBCL_BRA
        WHEN 1 THEN cat.resLineique_CAT
        WHEN 2 THEN lty.resLineique_LTY
        ELSE 0 END AS [R(Ohm/km)],
    CASE b.idBCL_BRA
        WHEN 1 THEN cat.indLineique_CAT
        WHEN 2 THEN lty.indLineique_LTY
        ELSE 0 END AS [X(Ohm/km)],
    CASE b.idBCL_BRA
        WHEN 1 THEN cat.courantAdmissible_CAT
        WHEN 2 THEN lty.courantAdmissible_LTY
        ELSE 0 END AS [Ampacity(A)],
    CASE b.idBCL_BRA
        WHEN 1 THEN cat.section_CAT
        WHEN 2 THEN lty.section_LTY
        ELSE 0 END AS [Section(mm2)],
    CASE b.idBCL_BRA
        WHEN 1 THEN cat.materiel_CAT
        WHEN 2 THEN lty.materiel_LTY
        ELSE 'Unknown' END AS [Cu/Al],
    CASE b.idBCL_BRA
        WHEN 1 THEN 'Cable'
        WHEN 2 THEN 'Line'
        ELSE 'Unknown' END AS [Cable/Line],
    CONCAT('POINT (', n1.coordNationalX_NOD, ' ', n1.coordNationalY_NOD, ')') AS From_XY,
    CONCAT('POINT (', n2.coordNationalX_NOD, ' ', n2.coordNationalY_NOD, ')') AS To_XY
FROM noeud_NOD n1
INNER JOIN composant_COP cop1 ON cop1.idNOD_COP = n1.id_NOD
INNER JOIN connecteurComplexe_CNX cnx1 ON cop1.id_COP = cnx1.idCOP_CNX
INNER JOIN connecteurComplexe_CNX cnx2 ON cnx1.idCNX_CNX = cnx2.id_CNX
INNER JOIN branche_BRA b ON b.id_BRA = cnx2.idBRA_CNX
INNER JOIN composant_COP cop2 ON cop2.id_COP = (
    SELECT TOP 1 cnx4.idCOP_CNX 
    FROM connecteurComplexe_CNX cnx3
    INNER JOIN connecteurComplexe_CNX cnx4 ON cnx3.idCNX_CNX = cnx4.id_CNX
    WHERE cnx3.idBRA_CNX = b.id_BRA AND cnx4.idCOP_CNX != cop1.id_COP
)
INNER JOIN noeud_NOD n2 ON n2.id_NOD = cop2.idNOD_COP
LEFT JOIN cable_CAB cab ON cab.idBRA_CAB = b.id_BRA
LEFT JOIN nCableType_CAT cat ON cat.id_CAT = cab.idCAT_CAB
LEFT JOIN ligne_LIG lig ON lig.idBRA_LIG = b.id_BRA
LEFT JOIN nLigneType_LTY lty ON lty.id_LTY = lig.idLTY_LIG
WHERE n1.id_NOD = 1
AND n1.idNCL_NOD = 1
ORDER BY b.id_BRA