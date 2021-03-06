/* $Id$  */
INSERT INTO contact_type ( contact_type_name,sort_order ) VALUES ( 'other',100 );
INSERT INTO contact_type ( contact_type_name ) VALUES ( 'investigator' );
INSERT INTO contact_type ( contact_type_name ) VALUES ( 'vendor' );
INSERT INTO contact_type ( contact_type_name ) VALUES ( 'academic_lab' );
INSERT INTO contact_type ( contact_type_name ) VALUES ( 'commercial_lab' );
INSERT INTO contact_type ( contact_type_name ) VALUES ( 'sales_rep' );
INSERT INTO contact_type ( contact_type_name ) VALUES ( 'technical_rep' );
INSERT INTO contact_type ( contact_type_name,sort_order ) VALUES ( 'data_producer',4 );
INSERT INTO contact_type ( contact_type_name,sort_order ) VALUES ( 'data_curator',5 );
INSERT INTO contact_type ( contact_type_name,sort_order ) VALUES ( 'lab_technician',5 );


INSERT INTO privilege ( privilege_id,name,sort_order ) VALUES ( 10,'administrator',5 );
INSERT INTO privilege ( privilege_id,name,sort_order ) VALUES ( 20,'data_modifier',4 );
INSERT INTO privilege ( privilege_id,name,sort_order ) VALUES ( 25,'data_groupmodifier',3 );
INSERT INTO privilege ( privilege_id,name,sort_order ) VALUES ( 30,'data_writer',2 );
INSERT INTO privilege ( privilege_id,name,sort_order ) VALUES ( 40,'data_reader',1 );
INSERT INTO privilege ( privilege_id,name,sort_order ) VALUES ( 50,'none',5 );


INSERT INTO record_status ( record_status_id,name,sort_order ) VALUES ( 'N','Normal',1 );
INSERT INTO record_status ( record_status_id,name,sort_order ) VALUES ( 'L','Locked',2 );
INSERT INTO record_status ( record_status_id,name,sort_order ) VALUES ( 'M','Modifiable',3 );
INSERT INTO record_status ( record_status_id,name,sort_order ) VALUES ( 'D','Deleted',4 );


INSERT INTO work_group ( work_group_name,sort_order,primary_contact_id,comment ) VALUES ( 'Admin',100,1,'Administrators with nearly full privilege' );
INSERT INTO work_group ( work_group_name,sort_order,primary_contact_id,comment ) VALUES ( 'Other',101,1,'Default group with almost no privilege' );
INSERT INTO work_group ( work_group_name,sort_order,primary_contact_id,comment ) VALUES ( 'Guest',99,1,'Guest work group with access to only public facilities' );
INSERT INTO work_group ( work_group_name,sort_order,primary_contact_id,comment ) VALUES ( 'Developer',98,1,'SBEAMS software developer group' );


INSERT INTO organization_type ( organization_type_name,sort_order ) VALUES ( 'Non-profit organization',10 );
INSERT INTO organization_type ( organization_type_name,sort_order ) VALUES ( 'For-profit company',20 );
INSERT INTO organization_type ( organization_type_name,sort_order ) VALUES ( 'Department',30 );
INSERT INTO organization_type ( organization_type_name,sort_order ) VALUES ( 'Group',40 );
INSERT INTO organization_type ( organization_type_name,sort_order ) VALUES ( 'Lab',50 );
INSERT INTO organization_type ( organization_type_name,sort_order ) VALUES ( 'UNKNOWN',999 );


INSERT INTO organization ( organization,organization_type_id,street,
  city,province_state,country,postal_code,phone,fax,email,
  uri,sort_order )
  VALUES ( 'Institute for Systems Biology',1,'1441 N 34th St','Seattle','WA',
  'USA','98103-8904','206-732-1200','206-732-1299','webmaster@systemsbiology.org',
  'http://www.systemsbiology.org/',5 );
INSERT INTO organization ( organization,organization_type_id,street,
  city,province_state,country,postal_code,phone,fax,email,
  uri,created_by_id,modified_by_id )
  VALUES ( 'UNKNOWN',6,'','','',
  '','','','','',
  '',1,1 );


INSERT INTO contact ( last_name,first_name,middle_name,contact_type_id,
  organization_id,email,uri )
  VALUES ( 'Administrator','SBEAMS','',8,
  1,'sbeams@localdomain.org',
  'http://localhost/' );
INSERT INTO contact ( last_name,first_name,middle_name,contact_type_id,job_title,
  organization_id,email,uri )
  VALUES ( 'Deutsch','Eric','W',9,'Sr. Database Architect',
  1,'edeutsch@systemsbiology.org',
  'http://db.systemsbiology.net/~edeutsch/' );

/* Do not change this unless you REALLY think it's important */
INSERT INTO user_login ( contact_id,username,password,privilege_id )
  VALUES ( 1,'admin','****',10 );


INSERT INTO user_work_group ( contact_id,work_group_id,privilege_id ) VALUES ( 1,1,10 );


INSERT INTO table_group_security ( table_group,work_group_id,privilege_id ) VALUES ( 'admin',1,10 );
INSERT INTO table_group_security ( table_group,work_group_id,privilege_id ) VALUES ( 'common',1,10 );
INSERT INTO table_group_security ( table_group,work_group_id,privilege_id ) VALUES ( 'infrastructure',1,10 );
INSERT INTO table_group_security ( table_group,work_group_id,privilege_id ) VALUES ( 'project',1,10 );
INSERT INTO table_group_security ( table_group,work_group_id,privilege_id ) VALUES ( 'rowprivate',1,10 );
INSERT INTO table_group_security ( table_group,work_group_id,privilege_id ) VALUES ( 'rowprivate',2,30 );
INSERT INTO table_group_security ( table_group,work_group_id,privilege_id ) VALUES ( 'rowprivate',3,30 );


INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'yesno','Y','YES',10 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'yesno','N','NO',20 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'input_form_options','minimum_detail','Minimum Detail',10 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'input_form_options','medium_detail','Medium Detail',20 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'input_form_options','full_detail','Full Detail',30 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'job_status','Not Yet Submitted','Not Yet Submitted', 10 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'job_status','Submitted','Submitted', 20 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'job_status','Started','Started', 30 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'job_status','Finished','Finished', 40 );

INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'gender','M','Male',10 );
INSERT INTO misc_option ( option_type,option_key,option_value,sort_order )
VALUES ( 'gender','F','Female',20 );



/* EDIT BELOW: "LastName", "First", "NISusername" to reflect yourself */
INSERT INTO contact ( last_name,first_name,middle_name,contact_type_id, organization_id ) VALUES ( 'LastName','First','',9,2 );
INSERT INTO user_login ( contact_id,username,password,privilege_id ) VALUES ( 3,'NISusername',NULL,10 );

/* If you choose to set up an SBEAMS password for yourself, do it here */
/* Read the notes in the sbeams.installnotes first, though! */
/* EDIT ABOVE: */


INSERT INTO user_work_group ( contact_id,work_group_id,privilege_id ) VALUES ( 3,1,10 );
INSERT INTO user_work_group ( contact_id,work_group_id,privilege_id ) VALUES ( 3,4,10 );
