/*
 * Business Process Definition: Bank Holiday Approval (bankholiday_approval_wf)
 */

/* Cases table and object type */
create table bankholiday_approval_wf_cases (case_id integer primary key references wf_cases on delete cascade);

/* Declare the object type */
create function inline_0 () returns integer as $$
begin
	PERFORM workflow__create_workflow (
		'bankholiday_approval_wf',
		'Bank Holiday Approval WF',
		'Bank Holiday Approval WF',
		'Approval workflow for public holidays. The approval is statically assigned to HR Managers.',
		'bankholiday_approval_wf_cases',
		'case_id'
	);
	return null;
end;$$ language 'plpgsql';
select inline_0 ();
drop function inline_0 ();

/***** Places*****/
select workflow__add_place('bankholiday_approval_wf','before_review','Ready to Review',10);
select workflow__add_place('bankholiday_approval_wf','before_approved','Ready to Approved',100);
select workflow__add_place('bankholiday_approval_wf','before_deleted','Ready to Deleted',100);
select workflow__add_place('bankholiday_approval_wf','end','Process finished',100);
select workflow__add_place('bankholiday_approval_wf','start','Start',100);

/****** Roles*****/
select workflow__add_role ('bankholiday_approval_wf','approved','Approved',3);
select workflow__add_role ('bankholiday_approval_wf','deleted','Deleted',4);
select workflow__add_role ('bankholiday_approval_wf','approve','Approve',2);
select workflow__add_role ('bankholiday_approval_wf','modify','Modify',1);

/****** Transitions*****/
select workflow__add_transition ('bankholiday_approval_wf','modify','Modify','modify',1,'user');
select workflow__add_transition ('bankholiday_approval_wf','approve','Approve','approve',2,'user');
select workflow__add_transition ('bankholiday_approval_wf','approved','Approved','approved',3,'automatic');
select workflow__add_transition ('bankholiday_approval_wf','deleted','Deleted','deleted',4,'automatic');

/****** Arcs*****/
select workflow__add_arc ('bankholiday_approval_wf','approve','before_review','out','#','','Rejected');
select workflow__add_arc ('bankholiday_approval_wf','approve','start','in','','','');
select workflow__add_arc ('bankholiday_approval_wf','approve','before_approved','out','wf_callback__guard_attribute_true','review_reject_p','Approved');
select workflow__add_arc ('bankholiday_approval_wf','approved','before_approved','in','','','');
select workflow__add_arc ('bankholiday_approval_wf','approved','end','out','','','');
select workflow__add_arc ('bankholiday_approval_wf','deleted','before_deleted','in','','','');
select workflow__add_arc ('bankholiday_approval_wf','deleted','end','out','','','');
select workflow__add_arc ('bankholiday_approval_wf','modify','before_review','in','','','');
select workflow__add_arc ('bankholiday_approval_wf','modify','start','out','','','');

/****** Attributes*****/
select workflow__create_attribute('bankholiday_approval_wf','review_reject_p','boolean','Approve the Absence?', null, null, null,'t', 1, 1, null, 'generic');
select workflow__add_trans_attribute_map('bankholiday_approval_wf','approve','review_reject_p',1);

/****** Transition-role-assignment-map*****/
insert into wf_context_transition_info(context_key,workflow_key,transition_key,estimated_minutes,instructions,enable_callback,enable_custom_arg,fire_callback,fire_custom_arg,time_callback,time_custom_arg,deadline_callback,deadline_custom_arg,deadline_attribute_name,hold_timeout_callback,hold_timeout_custom_arg,notification_callback,notification_custom_arg,unassigned_callback,unassigned_custom_arg) values ('default','bankholiday_approval_wf','approved',0,'','','','im_workflow__set_object_status_id','16000','','','','','','','','','','','');
insert into wf_context_transition_info(context_key,workflow_key,transition_key,estimated_minutes,instructions,enable_callback,enable_custom_arg,fire_callback,fire_custom_arg,time_callback,time_custom_arg,deadline_callback,deadline_custom_arg,deadline_attribute_name,hold_timeout_callback,hold_timeout_custom_arg,notification_callback,notification_custom_arg,unassigned_callback,unassigned_custom_arg) values ('default','bankholiday_approval_wf','deleted',0,'','','','im_workflow__set_object_status_id','16002','','','','','','','','','','','');
insert into wf_context_transition_info(context_key,workflow_key,transition_key,estimated_minutes,instructions,enable_callback,enable_custom_arg,fire_callback,fire_custom_arg,time_callback,time_custom_arg,deadline_callback,deadline_custom_arg,deadline_attribute_name,hold_timeout_callback,hold_timeout_custom_arg,notification_callback,notification_custom_arg,unassigned_callback,unassigned_custom_arg) values ('default','bankholiday_approval_wf','modify',5,'','im_workflow__set_object_status_id','16006','im_workflow__set_object_status_id','16004','','','','','','','','','','im_workflow__assign_to_owner','');
insert into wf_context_transition_info(context_key,workflow_key,transition_key,estimated_minutes,instructions,enable_callback,enable_custom_arg,fire_callback,fire_custom_arg,time_callback,time_custom_arg,deadline_callback,deadline_custom_arg,deadline_attribute_name,hold_timeout_callback,hold_timeout_custom_arg,notification_callback,notification_custom_arg,unassigned_callback,unassigned_custom_arg) values ('default','bankholiday_approval_wf','approve',5,'','','','','','','','','','','','','','','','');

/** Context/Role info */
/** Context Task Panels* (for context = default)*/
insert into wf_context_task_panels (context_key,workflow_key,transition_key,sort_order,header,template_url,overrides_action_p,overrides_both_panels_p,only_display_when_started_p) values ('default','bankholiday_approval_wf','approve',1,'Approve Absence','/packages/intranet-timesheet2-workflow/www/absences/absence-panel','f','f','f');
insert into wf_context_task_panels (context_key,workflow_key,transition_key,sort_order,header,template_url,overrides_action_p,overrides_both_panels_p,only_display_when_started_p) values ('default','bankholiday_approval_wf','modify',1,'Modify Absence','/packages/intranet-timesheet2-workflow/www/absences/absence-panel','f','f','f');

/** Static Assignments */
insert into wf_context_assignments (context_key, workflow_key, role_key, party_id) 
values ('default', 'bankholiday_approval_wf', 'approve', (select group_id from groups where group_name = 'Accounting'));
