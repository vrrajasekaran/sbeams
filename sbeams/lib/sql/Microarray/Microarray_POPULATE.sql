
--INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
--VALUES ( 'BSH_sort_options','experiment_tag,set_tag,S.file_root,SH.cross_corr_rank,SH.hit_index','Exp, DB, file_root, Rxc',10 );

INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_display_options','AllConditions','Show all data if one condition meets criteria',30 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_display_options','PivotConditions','Pivot Conditions as columns',40 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_display_options','CoalesceReporters','Coalesce Multiple Reporters',45 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_display_options','BSDesc','Display BioSequence Descriptions',50 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_display_options','ShowSQL','Show SQL Query',60 );

INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.log10_ratio','log10 Ratio',100 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.log10_uncertainty','log10 Uncertainty',110 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.log10_std_deviation','log10 Std Dev',120 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.lambda','Lambda',125 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.mu_x','mu X',130 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.mu_y','mu Y',140 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.mean_intensity','Mean Level',150 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.quality_flag','Quality Flag',160 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GE_data_columns','GE.mean_intensity_uncertainty','Mean Intensity Uncertainty',170 );

INSERT INTO gene_ontology_type ( gene_ontology_name_type )
VALUES ( 'Gene Ontology Biological Process' );
INSERT INTO gene_ontology_type ( gene_ontology_name_type )
VALUES ( 'Gene Ontology Cellular Component' );
INSERT INTO gene_ontology_type ( gene_ontology_name_type )
VALUES ( 'Gene Ontology Molecular Function' );


INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GI_data_columns','gi.signal','Signal Intensity',10 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GI_data_columns','gi.detection_call','Detection Call',20 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GI_data_columns','gi.detection_p_value','Detection P-value',30 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GI_data_columns','gi.protocol_id','R_CHP Analysis Protocol',40 );

INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GI_display_options','AllConditions','Show all data if one condition meets criteria',10 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GI_display_options','PivotConditions','Pivot Array Samples as columns',20 );
INSERT INTO query_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'GI_display_options','ShowSQL','Show SQL Query',30 );
