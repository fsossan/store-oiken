-- Verify substation node 1 (CTMT1078) owns these components
SELECT 
    n.id_NOD,
    n.code_NOD,
    cop.id_COP,
    cop.idNDE_COP,
    cop.idCCL_COP,
    cop.idNIV_COP
FROM noeud_NOD n
INNER JOIN composant_COP cop ON cop.idNOD_COP = n.id_NOD
WHERE n.id_NOD = 1
ORDER BY cop.idCCL_COP