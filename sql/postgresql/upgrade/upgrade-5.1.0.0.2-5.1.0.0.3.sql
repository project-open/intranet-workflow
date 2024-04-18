-- upgrade-5.1.0.0.2-5.1.0.0.3.sql
SELECT acs_log__debug('/packages/intranet-workflow/sql/postgresql/upgrade/upgrade-5.1.0.0.2-5.1.0.0.3.sql','');


-- ------------------------------------------------------
-- Unassigned callback that assigns the transition to the supervisor of the owner
-- of the underlying object, or use custom_arg as a default
--
create or replace function im_workflow__assign_to_supervisor (integer, text)
returns integer as $$
declare
	p_task_id		alias for $1;
	p_custom_arg		alias for $2;
	v_case_id		integer;	v_object_id		integer;
	v_creation_user		integer;	v_creation_ip		varchar;
	v_journal_id		integer;	v_object_type		varchar;
	v_owner_id		integer;	v_owner_name		varchar;
	v_supervisor_id		integer;	v_supervisor_name	varchar;
	v_transition_key	varchar;	v_default_party_id	integer;
	v_str			text;
	row			RECORD;
begin
	-- Get information about the transition and the "environment"
	select	tr.transition_key, t.case_id, c.object_id, o.creation_user, o.creation_ip, o.object_type
	into	v_transition_key, v_case_id, v_object_id, v_creation_user, v_creation_ip, v_object_type
	from	wf_tasks t, wf_cases c, wf_transitions tr, acs_objects o
	where	t.task_id = p_task_id
		and t.case_id = c.case_id
		and o.object_id = t.case_id
		and t.workflow_key = tr.workflow_key
		and t.transition_key = tr.transition_key;

	select	e.employee_id, im_name_from_user_id(e.employee_id), 
		e.supervisor_id, im_name_from_user_id(e.supervisor_id)
	into	v_owner_id, v_owner_name, 
		v_supervisor_id, v_supervisor_name
	from	im_employees e
	where	e.employee_id = v_creation_user;

	IF v_supervisor_id is not null THEN
		v_journal_id := journal_entry__new(
		    null, v_case_id,
		    v_transition_key || ' assign_to_supervisor ' || v_supervisor_name,
		    v_transition_key || ' assign_to_supervisor ' || v_supervisor_name,
		    now(), v_creation_user, v_creation_ip,
		    'Assigning to ' || v_supervisor_name || ', the supervisor of ' || v_owner_name || '.'
		);
		PERFORM workflow_case__add_task_assignment(p_task_id, v_supervisor_id, 'f');
		PERFORM workflow_case__notify_assignee (p_task_id, v_supervisor_id, null, null, 
			'wf_' || v_object_type || '_assignment_notif');

		return 0;
	END IF;

	-- No supervisor found, assign to custom_arg party_id (user or group)
	RAISE NOTICE 'im_workflow__assign_to_supervisor(task_id=%, oid=%): No supervisor of object creator, assigning to party_id in custom_arg="%" ', p_task_id, v_object_id, p_custom_arg;

	-- Cast to integer from parties.party_id. NULL argument gracefully handled or use global default
	select party_id into v_default_party_id from parties where party_id::varchar = p_custom_arg;
	IF v_default_party_id is null THEN
		select group_id into v_default_party_id from groups where group_name = 'Senior Managers';
	END IF;

	IF v_default_party_id is not null THEN
		RAISE NOTICE 'im_workflow__assign_to_supervisor(task_id=%, oid=%): Assigning to party_id in custom_arg="%" ', p_task_id, v_object_id, p_custom_arg;
		v_journal_id := journal_entry__new(
		    null, v_case_id,
		    v_transition_key || ' assign_to_default ' || acs_object__name(v_default_party_id),
		    v_transition_key || ' assign_to_default ' || acs_object__name(v_default_party_id),
		    now(), v_creation_user, v_creation_ip,
		    'No supervisor found, assigning to default party ' || acs_object__name(v_default_party_id)
		);
		PERFORM workflow_case__add_task_assignment(p_task_id, v_default_party_id, 'f');
		PERFORM workflow_case__notify_assignee (p_task_id, v_default_party_id, null, null, 
			'wf_' || v_object_type || '_assignment_notif');

		return 0;
	END IF;

end;$$ language 'plpgsql';

