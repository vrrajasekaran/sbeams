
DROP INDEX biosequence_annotated_gene.idx_biosequence_id
DROP INDEX biosequence_annotated_gene.idx_annotated_gene_id

TRUNCATE TABLE biosequence_annotated_gene

--------

-- Yeast
SELECT * from biosequence_set WHERE set_tag LIKE 'YeastORF%'
INSERT INTO biosequence_annotated_gene
SELECT BS.biosequence_id,AG.annotated_gene_id
  FROM biosequence BS
  JOIN biosequence_set BSS ON ( BS.biosequence_set_id = BSS.biosequence_set_id )
  JOIN BioLink..annotated_gene AG
       ON ( BS.biosequence_gene_name = AG.gene_name
            OR BS.biosequence_accession = AG.gene_accession
            OR BS.biosequence_gene_name = AG.gene_accession )
 WHERE BSS.set_tag LIKE 'YeastORF%'
   AND AG.organism_namespace_id=2


-- Drosophila
SELECT * from biosequence_set WHERE set_tag LIKE 'Dros%'
INSERT INTO biosequence_annotated_gene
SELECT BS.biosequence_id,AG.annotated_gene_id
  FROM biosequence BS
  JOIN biosequence_set BSS ON ( BS.biosequence_set_id = BSS.biosequence_set_id )
  JOIN BioLink..annotated_gene AG
       ON ( BS.biosequence_accession = AG.gene_accession
         OR BS.biosequence_gene_name = AG.gene_accession )
 WHERE BSS.set_tag LIKE 'Dros%'
   AND AG.organism_namespace_id=1


-- Arabidopsis
INSERT INTO biosequence_annotated_gene
SELECT BS.biosequence_id,AG.annotated_gene_id
  FROM biosequence BS
  JOIN biosequence_set BSS ON ( BS.biosequence_set_id = BSS.biosequence_set_id )
  JOIN BioLink..annotated_gene AG ON ( BS.biosequence_accession = AG.gene_accession )
 WHERE BSS.set_tag LIKE 'ATH%'
   AND AG.organism_namespace_id=6


-- Human NCI biosequence_sets
SELECT * from biosequence_set WHERE set_tag LIKE 'HuNCI%' OR set_tag LIKE 'HsNCI%'
INSERT INTO biosequence_annotated_gene
SELECT BS.biosequence_id,AG.annotated_gene_id
  FROM biosequence BS
  JOIN biosequence_set BSS ON ( BS.biosequence_set_id = BSS.biosequence_set_id )
  JOIN BioLink..annotated_gene AG ON ( BS.biosequence_accession = AG.gene_accession )
 WHERE BSS.set_tag LIKE 'HuNCI%'
    OR BSS.set_tag LIKE 'HsNCI%'
   AND AG.organism_namespace_id=5


-- Human IPI biosequence_sets
SELECT * from biosequence_set WHERE set_tag IN ( 'HuIPI','HepC','OldHuIPI','HIVHepCHuIPI200308' ) OR set_tag LIKE 'HsIPI_v%'
INSERT INTO biosequence_annotated_gene
SELECT DISTINCT BS.biosequence_id,AG.annotated_gene_id
  FROM biosequence BS
  JOIN biosequence_set BSS ON ( BS.biosequence_set_id = BSS.biosequence_set_id )
  JOIN BioLink..goa_association GOAA ON ( BS.biosequence_gene_name = GOAA.ipi_accession AND GOAA.ref_db_tag = 'UniProt' )
  JOIN BioLink..annotated_gene AG ON ( GOAA.ref_db_symbol = AG.gene_accession )
 WHERE BSS.set_tag IN ( 'HuIPI','HepC','OldHuIPI','HIVHepCHuIPI200308' )
    OR BSS.set_tag LIKE 'HsIPI_v%'
   AND AG.organism_namespace_id=5


INSERT INTO biosequence_annotated_gene
SELECT DISTINCT BS.biosequence_id,AG.annotated_gene_id
  FROM biosequence BS
  JOIN biosequence_set BSS ON ( BS.biosequence_set_id = BSS.biosequence_set_id )
  JOIN BioLink..goa_association GOAA ON ( BS.biosequence_gene_name = GOAA.ipi_accession AND GOAA.ref_db_tag = 'UniProt' )
  JOIN BioLink..annotated_gene AG ON ( GOAA.ref_db_symbol = AG.gene_accession )
 WHERE BSS.set_tag LIKE 'MmIPI%'
   AND AG.organism_namespace_id=5



CREATE NONCLUSTERED INDEX idx_biosequence_id ON dbo.biosequence_annotated_gene ( biosequence_id )
CREATE NONCLUSTERED INDEX idx_annotated_gene_id ON dbo.biosequence_annotated_gene ( annotated_gene_id )

-------

-- Testing queries:

SELECT COUNT(*) FROM biosequence_annotated_gene
 
SELECT TOP 100 * FROM biosequence_set
 
SELECT TOP 100 * FROM biosequence WHERE biosequence_set_id=2
 
SELECT * FRom BioLink..organism_namespace
 
SELECT TOP 100 * FROM BioLink..annotated_gene WHERE organism_namespace_id=2
 
SELECT TOP 100 * FROM BioLink..goa_association
 
SELECT TOP 100 * FROM BioLink..goa_xref

