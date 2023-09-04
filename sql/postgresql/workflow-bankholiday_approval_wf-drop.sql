

-- Remove bankholiday_approval_wf for absences of type Bank Holiday
update im_categories set aux_string1 = NULL where category_id = 5005 and aux_string1 = 'bankholiday_approval_wf';



-- Delete index
    	   delete from acs_object_context_index 
    	   where 
	   	 object_id in (
	   	 	select object_id 
		 	from acs_objects 
		 	where object_type = 'bankholiday_approval_wf'
	    	 ) OR
	   	 ancestor_id in (
	   	 	select object_id 
		 	from acs_objects 
		 	where object_type = 'bankholiday_approval_wf'
	    	 );

-- Reset the context ID from objects in the context of the WF (which one? Cases?)
       update acs_objects set context_id = null 
       where context_id in (
       	     select object_id 
	     from acs_objects 
	     where object_type = 'bankholiday_approval_wf'
       );


-- Delete tokens
delete from wf_tokens where workflow_key = 'bankholiday_approval_wf';

-- Delete attributes audit
delete from wf_attribute_value_audit where case_id in (select case_id from wf_cases where workflow_key = 'bankholiday_approval_wf');

-- Delete workflow cases
delete from acs_objects where object_type = 'bankholiday_approval_wf';


-- Delete cases
select workflow__delete_cases('bankholiday_approval_wf');

-- Drop table
drop table if exists bankholiday_approval_wf_cases;


-- Delete reference for REST objects metadata
delete from im_rest_object_types where object_type = 'bankholiday_approval_wf';

-- Delete the entire workflow (object?)
select workflow__drop_workflow('bankholiday_approval_wf');

