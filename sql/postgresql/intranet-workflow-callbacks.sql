-- /packages/intranet-workflow/sql/postgres/intranet-workflow-callbacks.sql
--
-- Copyright (c) 2003 - 2009 ]project-open[
--
-- All rights reserved. Please check
-- https://www.project-open.com/license/ for details.
--
-- @author frank.bergmann@project-open.com
-- @author klaus.hofeditz@project-open.com
-- @author malte.sussdorff@cognovis.de

-- ------------------------------------------------------------------
-- Generic Workflow Callbacks that work across Business Objects
-- ------------------------------------------------------------------

-- ------------------------------------------------------
-- Callback functions for Workflow
-- ------------------------------------------------------


-- ------------------------------------------------------
-- Enable callback that deletes all tokens in the systems except the one
-- for the current transition.
-- This function allows to deal with parallelism in the Petri-Net and
-- the situation that one approval path of severals is not OK.
--
-- The function will also "cancel" any started transitions, in order to
-- cancel parallel tasks that were already started.
--
-- p_custom_arg is not used.
--
create or replace function im_workflow__delete_all_other_tokens (integer, text, text)
returns integer as $body$
declare
	p_case_id		alias for $1;
	p_transition_key	alias for $2;
	p_custom_arg		alias for $3;

	v_task_id		integer;	v_case_id		integer;
	v_object_id		integer;	v_creation_user		integer;
	v_creation_ip		varchar;	v_journal_id		integer;
	v_transition_key	varchar;	v_workflow_key		varchar;
	v_status		varchar;
	v_str			text;
	row			RECORD;
begin
	-- Select out some frequently used variables of the environment
	select  c.object_id, c.workflow_key, task_id, c.case_id
	into	v_object_id, v_workflow_key, v_task_id, v_case_id
	from	wf_tasks t, wf_cases c
	where   c.case_id = p_case_id
		and t.case_id = c.case_id
		and t.workflow_key = c.workflow_key
		and t.transition_key = p_transition_key;

	-- Get some information about the object
	select	o.creation_user into v_creation_user from acs_objects o where o.object_id = v_object_id;

	v_journal_id := journal_entry__new(
		null, v_case_id,
		v_transition_key || ' set_object_status_id ' || im_category_from_id(p_custom_arg::integer),
		v_transition_key || ' set_object_status_id ' || im_category_from_id(p_custom_arg::integer),
		now(), v_creation_user, v_creation_ip,
		'Deleting all other tokens and resetting transitions, except for "' || p_transition_key || '".'
	);

	-- Cancel all started tasks. This will result in releasing the tokens to their places.
	FOR row IN
		select	*
		from	wf_tasks
		where	case_id = p_case_id and
			state = 'started'
	LOOP
		-- PERFORM acs_log__debug('im_workflow__delete_all_other_tokens', 'Cancel task '||row.task_id);
		PERFORM workflow_case__cancel_task (row.task_id, v_journal_id);
	END LOOP;

	-- Delete all "free" tokens
	FOR row IN
		select	*
		from	wf_tokens
		where	case_id = p_case_id and
			state = 'free'
	LOOP
		-- PERFORM acs_log__debug('im_workflow__delete_all_other_tokens', 'Deleting token '||row.token_id||' in place '||row.place_key);
		delete from wf_tokens where token_id = row.token_id;
	END LOOP;

	-- For all places that link to the current (new!) transition
	-- create a new token to enable the current transition
	FOR row IN
		select	*
		from	wf_arcs
		where	workflow_key = v_workflow_key and
			transition_key = p_transition_key and 
			direction = 'in'
	LOOP
		-- PERFORM acs_log__debug('im_workflow__delete_all_other_tokens', 'Add token in place '||row.place_key);
		PERFORM workflow_case__add_token (p_case_id, row.place_key, null);
	END LOOP;

	return 0;
end; $body$ language 'plpgsql';



-- ------------------------------------------------------
-- Enable callback that skips (fires) the transition if the underlying 
-- WF object has the specified status. This callback is used for example 
-- to bypass a workflow if the object is already approved.
--
create or replace function im_workflow__skip_on_status_id (integer, text, text)
returns integer as $$
declare
	p_case_id		alias for $1;
	p_transition_key	alias for $2;
	p_custom_arg		alias for $3;

	v_task_id		integer;
	v_case_id		integer;
	v_object_id		integer;
	v_creation_user		integer;
	v_creation_ip		varchar;
	v_journal_id		integer;
	v_transition_key	varchar;
	v_workflow_key		varchar;

	v_status_id		varchar;
begin
	-- Select out some frequently used variables of the environment
	select	c.object_id, c.workflow_key, c.creation_ip, task_id, c.case_id, 
		im_biz_object__get_status_id(c.object_id)
	into	v_object_id, v_workflow_key, v_creation_ip, v_task_id, v_case_id,
		v_status_id
	from	wf_tasks t, wf_cases c
	where	c.case_id = p_case_id
		and t.case_id = c.case_id
		and t.workflow_key = c.workflow_key
		and t.transition_key = p_transition_key;

	-- Get some information about the object
	select	o.creation_user into v_creation_user from acs_objects o where o.object_id = v_object_id;

	IF v_status_id = p_custom_arg::integer THEN
		v_journal_id := journal_entry__new(
		    null, v_case_id,
		    v_transition_key || ' skipping because of status ' || im_category_from_id(v_status_id),
		    v_transition_key || ' skipping because of status ' || im_category_from_id(v_status_id),
		    now(), v_creation_user, v_creation_ip,
		    'Skipping transition with status: ' || im_category_from_id(v_status_id)
		);
		-- Consume tokens from incoming places and put out tokens to outgoing places
		PERFORM workflow_case__fire_transition_internal (v_task_id, v_journal_id);
	END IF;
	return 0;
end;$$ language 'plpgsql';


-- ------------------------------------------------------
-- Enable callback that sets the status of the underlying object
--
create or replace function im_workflow__set_object_status_id (integer, text, text)
returns integer as $$
declare
	p_case_id		alias for $1;
	p_transition_key	alias for $2;
	p_custom_arg		alias for $3;
	v_task_id		integer;	v_case_id		integer;
	v_object_id		integer;	v_creation_user		integer;
	v_creation_ip		varchar;	v_journal_id		integer;
	v_transition_key	varchar;	v_workflow_key		varchar;
	v_status		varchar;
	v_str			text;
	row			RECORD;
begin
	-- Select out some frequently used variables of the environment
	select	c.object_id, c.workflow_key, task_id, c.case_id
	into	v_object_id, v_workflow_key, v_task_id, v_case_id
	from	wf_tasks t, wf_cases c
	where	c.case_id = p_case_id
		and t.case_id = c.case_id
		and t.workflow_key = c.workflow_key
		and t.transition_key = p_transition_key;

	-- Get some information about the object
	select	o.creation_user into v_creation_user from acs_objects o where o.object_id = v_object_id;

	v_journal_id := journal_entry__new(
	    null, v_case_id,
	    v_transition_key || ' set_object_status_id ' || im_category_from_id(p_custom_arg::integer),
	    v_transition_key || ' set_object_status_id ' || im_category_from_id(p_custom_arg::integer),
	    now(), v_creation_user, v_creation_ip,
	    'Setting the status of "' || acs_object__name(v_object_id) || '" to "' || 
	    im_category_from_id(p_custom_arg::integer) || '".'
	);

	PERFORM im_biz_object__set_status_id(v_object_id, p_custom_arg::integer);
	return 0;
end;$$ language 'plpgsql';



-- ------------------------------------------------------
-- Unassigned callback that assigns the transition to the owner of the underlying object.
--
create or replace function im_workflow__assign_to_owner (integer, text)
returns integer as $$
declare
	p_task_id		alias for $1;	p_custom_arg		alias for $2;
	v_case_id		integer;	v_object_id		integer;
	v_creation_user		integer;	v_creation_ip		varchar;
	v_journal_id		integer;	v_object_type		varchar;
	v_transition_key	varchar;	v_owner_id		integer;
	v_owner_name		varchar;
begin
	-- Get information about the transition and the "environment"
	select	t.case_id, c.object_id, o.creation_user, o.creation_ip, o.object_type, tr.transition_key
	into	v_case_id, v_object_id, v_creation_user, v_creation_ip, v_object_type, v_transition_key
	from	wf_tasks t, wf_cases c, wf_transitions tr, acs_objects o
	where	t.task_id = p_task_id
		and t.case_id = c.case_id
		and o.object_id = t.case_id
		and t.workflow_key = tr.workflow_key
		and t.transition_key = tr.transition_key;

	IF v_object_id is not null THEN
		-- Use the real creation_user of the underlying BizObject if present
		select	bizobj.creation_user, im_name_from_user_id(bizobj.creation_user) into v_owner_id, v_owner_name
		from	acs_objects bizobj
		where	bizobj.object_id = v_object_id;
	ELSE
		-- Use the creation_user of the WF as a default
		select	v_creation_user, im_name_from_user_id(v_creation_user) into v_owner_id, v_owner_name;
	END IF;

	IF v_owner_id is not null THEN
		v_journal_id := journal_entry__new(
		    null, v_case_id,
		    v_transition_key || ' assign_to_owner ' || v_owner_name,
		    v_transition_key || ' assign_to_owner ' || v_owner_name,
		    now(), v_creation_user, v_creation_ip,
		    'Assigning to ' || v_owner_name || ', the owner of ' || 
		    acs_object__name(v_object_id) || '.'
		);
		PERFORM workflow_case__add_task_assignment(p_task_id, v_owner_id, 'f');
		RAISE NOTICE 'im_workflow__assign_to_owner: workflow_case__notify_assignee (%,%,%)',
		     p_task_id, v_owner_id, 'wf_' || v_object_type || '_assignment_notif';
		PERFORM workflow_case__notify_assignee (p_task_id, v_owner_id, null, null, 
			'wf_' || v_object_type || '_assignment_notif');
	END IF;
	return 0;
end;$$ language 'plpgsql';


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

	RAISE NOTICE 'im_workflow__assign_to_supervisor(task_id=%, oid=%): No supervisor found, assigning to custom_arg="%" ', 
		p_task_id, v_object_id, p_custom_arg;

	-- Cast to integer from parties.party_id. NULL argument gracefully handled or use global default
	v_default_party_id := (select party_id from parties where party_id::varchar = p_custom_arg);
	IF v_default_party_id is null THEN v_default_party_id := (select group_id from groups where group_name = 'Senior Managers'); END IF;

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
	return 0;
end;$$ language 'plpgsql';


-- ------------------------------------------------------
-- Unassigned callback that assigns the transition to the group in the custom_arg
--
create or replace function im_workflow__assign_to_group (integer, text)
returns integer as $$
declare
	p_task_id		alias for $1;
	p_custom_arg		alias for $2;

	v_transition_key	varchar;	v_object_type		varchar;
	v_case_id		integer;	v_object_id		integer;
	v_creation_user		integer;	v_creation_ip		varchar;

	v_group_id		integer;	v_group_name		varchar;

	v_journal_id		integer;	
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

	select	group_id, group_name into v_group_id, v_group_name from groups
	where	trim(lower(group_name)) = trim(lower(p_custom_arg));

	IF v_group_id is not null THEN
		v_journal_id := journal_entry__new(
		    null, v_case_id,
		    v_transition_key || ' assign_to_group ' || v_group_name,
		    v_transition_key || ' assign_to_group ' || v_group_name,
		    now(), v_creation_user, v_creation_ip,
		    'Assigning to specified group ' || v_group_name
		);
		PERFORM workflow_case__add_task_assignment(p_task_id, v_group_id, 'f');
		PERFORM workflow_case__notify_assignee (p_task_id, v_group_id, null, null, 
			'wf_' || v_object_type || '_assignment_notif');
	END IF;
	return 0;
end;$$ language 'plpgsql';


create or replace function im_workflow__assign_to_group (integer, text, text)
returns integer as $$
declare
	p_case_id	       alias for $1;
	p_transition_key	alias for $2;
	p_custom_arg	    alias for $3;

	v_task_id		integer;	v_case_id		integer;
	v_creation_ip		varchar; 	v_creation_user		integer;
	v_object_id		integer;	v_object_type		varchar;
	v_journal_id		integer;
	v_transition_key	varchar;	v_workflow_key		varchar;

	v_group_id		integer;	v_group_name		varchar;
begin
	-- Select out some frequently used variables of the environment
	select	c.object_id, c.workflow_key, task_id, c.case_id, co.object_type, co.creation_ip
	into	v_object_id, v_workflow_key, v_task_id, v_case_id, v_object_type, v_creation_ip
	from	wf_tasks t, wf_cases c, acs_objects co
	where	c.case_id = p_case_id
		and c.case_id = co.object_id
		and t.case_id = c.case_id
		and t.workflow_key = c.workflow_key
		and t.transition_key = p_transition_key;

	select	group_id, group_name into v_group_id, v_group_name from groups
	where	trim(lower(group_name)) = trim(lower(p_custom_arg));

	-- Get some information about the object
	select	o.creation_user into v_creation_user from acs_objects o where o.object_id = v_object_id;

	IF v_group_id is not null THEN
		v_journal_id := journal_entry__new(
		    null, v_case_id,
		    v_transition_key || ' assign_to_group ' || v_group_name,
		    v_transition_key || ' assign_to_group ' || v_group_name,
		    now(), v_creation_user, v_creation_ip,
		    'Assigning to specified group ' || v_group_name
		);
		PERFORM workflow_case__add_task_assignment(v_task_id, v_group_id, 'f');
		PERFORM workflow_case__notify_assignee (v_task_id, v_group_id, null, null, 
			'wf_' || v_object_type || '_assignment_notif');
	END IF;
	return 0;
end;$$ language 'plpgsql';



-- ------------------------------------------------------
-- Assign the transition to project members with role "Project Admin".
-- (The project manager is automatically assigned as project member with
-- this role, but there may be additional persons in this role).

create or replace function im_workflow__assign_to_project_admins (integer, text, text)
returns integer as $$
declare
	p_case_id		alias for $1;
	p_transition_key	alias for $2;
	p_custom_arg		alias for $3;

	v_task_id		integer;	v_case_id		integer;
	v_creation_ip		varchar; 	v_creation_user		integer;
	v_object_id		integer;	v_object_type		varchar;
	v_journal_id		integer;
	v_transition_key	varchar;	v_workflow_key		varchar;

	row			RECORD;
begin
	-- Select out some frequently used variables of the environment
	select	c.object_id, c.workflow_key, task_id, c.case_id, co.object_type, co.creation_ip
	into	v_object_id, v_workflow_key, v_task_id, v_case_id, v_object_type, v_creation_ip
	from	wf_tasks t, wf_cases c, acs_objects co
	where	c.case_id = p_case_id
		and c.case_id = co.object_id
		and t.case_id = c.case_id
		and t.workflow_key = c.workflow_key
		and t.transition_key = p_transition_key;

	-- Get some information about the object
	select	o.creation_user into v_creation_user from acs_objects o where o.object_id = v_object_id;

	FOR row IN
		select	r.object_id_two as user_id, 
			im_name_from_user_id(r.object_id_two) as user_name
		from	wf_cases wfc,
			im_projects p,
			acs_rels r,
			im_biz_object_members bom
		where	wfc.case_id = v_case_id and
			wfc.object_id = p.project_id and
			r.object_id_one = p.project_id and
			r.rel_id = bom.rel_id and
			bom.object_role_id = 1301
	LOOP
		v_journal_id := journal_entry__new(
		    null, v_case_id,
		    v_transition_key || ' assign_to_user ' || row.user_name,
		    v_transition_key || ' assign_to_user ' || row.user_name,
		    now(), v_creation_user, v_creation_ip,
		    'Assigning to ' || row.user_name
		);
		PERFORM workflow_case__add_task_assignment(v_task_id, row.user_id, 'f');
		PERFORM workflow_case__notify_assignee (v_task_id, row.user_id, null, null, 
			'wf_' || v_object_type || '_assignment_notif');
	END LOOP;

	return 0;
end;$$ language 'plpgsql';



CREATE OR REPLACE FUNCTION im_workflow__assign_to_project_manager(integer, text)
RETURNS integer AS $BODY$
DECLARE
	p_task_id		alias for $1;
	p_custom_arg		alias for $2;
	v_transition_key	varchar;
	v_object_type		varchar;
	v_case_id		integer;
	v_object_id		integer;
	v_creation_user		integer;
	v_creation_ip		varchar;
	v_project_manager_id	integer;
	v_project_manager_name	varchar;
	v_journal_id		integer;
BEGIN
	-- Get information about the transition and the 'environment'
	select	tr.transition_key, t.case_id, c.object_id, o.creation_user, o.creation_ip, o.object_type
	into	v_transition_key, v_case_id, v_object_id, v_creation_user, v_creation_ip, v_object_type
	from	wf_tasks t, wf_cases c, wf_transitions tr, acs_objects o
	where	t.task_id = p_task_id and
		t.case_id = c.case_id and
		o.object_id = t.case_id and
		t.workflow_key = tr.workflow_key and
		t.transition_key = tr.transition_key;

	-- Get the PM based on the configuration object
	IF 'im_timesheet_conf_object' = v_object_type THEN
		select	p.project_lead_id into v_project_manager_id 
		from	im_projects p, im_timesheet_conf_objects co
		where	p.project_id = co.conf_project_id and
			co.conf_id = v_object_id;
	END IF;

	-- Get the PM based on the main project project_lead
	IF 'im_project' = v_object_type OR 'im_timesheet_task' = v_object_type OR 'im_ticket' = v_object_type THEN
		select	p.project_lead_id into v_project_manager_id 
		from	im_projects sub_p,
			im_projects main_p
		where	sub_p.project_id = v_object_id and
			main_p.tree_sortkey = tree_root_key(sub_p.tree_sortkey);
	END IF;

	select im_name_from_id(v_project_manager_id) into v_project_manager_name;

	RAISE NOTICE 'My projectmanager for % is % and called %', v_object_id, v_project_manager_id, v_project_manager_name;
	IF v_project_manager_id is not null THEN
		v_journal_id := journal_entry__new(
			null, v_case_id,
			v_transition_key || ' assign_to_project_manager ' || v_project_manager_name,
			v_transition_key || ' assign_to_project_manager ' || v_project_manager_name,
			now(), v_creation_user, v_creation_ip,
			'Assigning to user' || v_project_manager_name
		);
		PERFORM workflow_case__add_task_assignment(p_task_id, v_project_manager_id, 'f');
		PERFORM workflow_case__notify_assignee (p_task_id, v_project_manager_id, null, null,
			'wf_' || v_object_type || '_assignment_notif');
	END IF;
	return 0;
END; $BODY$ LANGUAGE 'plpgsql' VOLATILE;


-- Unassigned callback for financial documents to assign the projects supervisor
CREATE OR REPLACE FUNCTION im_workflow__assign_to_findoc_project_supervisor(integer, text)
RETURNS integer AS $BODY$
DECLARE
	p_task_id		alias for $1;
	p_custom_arg		alias for $2;
	v_transition_key	varchar;
	v_object_type		varchar;
	v_case_id		integer;
	v_object_id		integer;
	v_creation_user		integer;
	v_creation_ip		varchar;
	v_supervisor_id 	integer;
	v_supervisor_name	varchar;
	v_journal_id		integer;
BEGIN
	-- Get information about the transition and the 'environment'
	select	tr.transition_key, t.case_id, c.object_id, o.creation_user, o.creation_ip, o.object_type
	into	v_transition_key, v_case_id, v_object_id, v_creation_user, v_creation_ip, v_object_type
	from	wf_tasks t, wf_cases c, wf_transitions tr, acs_objects o
	where	t.task_id = p_task_id and
		t.case_id = c.case_id and
		o.object_id = t.case_id and
		t.workflow_key = tr.workflow_key and
		t.transition_key = tr.transition_key;

	-- From the financial document get the task and from there get
	-- the main_projects and extract its supervisor_id
	select	main_p.supervisor_id, im_name_from_id(main_p.supervisor_id)
	into	v_supervisor_id, v_supervisor_name -- take the supervisor from the main project
	from	im_costs c,
		im_projects p,
		im_projects main_p
	where	c.cost_id = v_object_id and	-- the WF is attached to a financial document
		c.project_id = p.project_id and	-- the cost is attached to a task
		main_p.tree_sortkey = tree_root_key(p.tree_sortkey); -- Get the main_project from any sub-level

	RAISE NOTICE 'The supervisor for % is % and called %', v_object_id, v_supervisor_id, v_supervisor_name;
	IF v_supervisor_id is not null THEN
		v_journal_id := journal_entry__new(
			null, v_case_id,
			v_transition_key || ' assign_to_supervisor ' || v_supervisor_name,
			v_transition_key || ' assign_to_supervisor ' || v_supervisor_name,
			now(), v_creation_user, v_creation_ip,
			'Assigning to user ' || v_supervisor_name || ', the supervisor of ' ||
			acs_object__name(v_object_id) || '.'
		);
		PERFORM workflow_case__add_task_assignment(p_task_id, v_supervisor_id, 'f');
		PERFORM workflow_case__notify_assignee (p_task_id, v_supervisor_id, null, null,
			'wf_' || v_object_type || '_assignment_notif');
	ELSE	
		-- IF the supervisor_id is NULL, then we will get 'stuck' workflows.
		-- However, these WFs are shown to the admin who can fix them.
		v_journal_id := journal_entry__new(
			null, v_case_id,
			v_transition_key || ' assign_to_supervisor ' || v_supervisor_name,
			v_transition_key || ' assign_to_supervisor ' || v_supervisor_name,
			now(), v_creation_user, v_creation_ip,
			'NOT assigning to any user, because there is no supervisor_id for project ' ||
			acs_object__name(v_object_id) || '.'
		);
	END IF;

	return 0;
END; $BODY$ LANGUAGE 'plpgsql' VOLATILE;









-- Unassigned callback for a financial document to assign a random senior manager who is not the project supervisor
CREATE OR REPLACE FUNCTION im_workflow__assign_to_findoc_project_non_supervising_senior_manager(integer, text)
RETURNS integer AS $BODY$
DECLARE
	p_task_id		alias for $1;
	p_custom_arg		alias for $2;
	v_transition_key	varchar;
	v_object_type		varchar;
	v_case_id		integer;
	v_object_id		integer;
	v_creation_user		integer;
	v_creation_ip		varchar;
	v_supervisor_id 	integer;
	v_supervisor_name	varchar;
	v_non_supervisor_id 	integer;
	v_non_supervisor_name	varchar;
	v_journal_id		integer;
BEGIN
	-- Get information about the transition and the 'environment'
	select	tr.transition_key, t.case_id, c.object_id, o.creation_user, o.creation_ip, o.object_type
	into	v_transition_key, v_case_id, v_object_id, v_creation_user, v_creation_ip, v_object_type
	from	wf_tasks t, wf_cases c, wf_transitions tr, acs_objects o
	where	t.task_id = p_task_id and
		t.case_id = c.case_id and
		o.object_id = t.case_id and
		t.workflow_key = tr.workflow_key and
		t.transition_key = tr.transition_key;

	-- From the financial document get the task and from there get
	-- the main_projects and extract its supervisor_id
	select	main_p.supervisor_id, im_name_from_id(main_p.supervisor_id)
	into	v_supervisor_id, v_supervisor_name -- take the supervisor from the main project
	from	im_costs c,
		im_projects p,
		im_projects main_p
	where	c.cost_id = v_object_id and	-- the WF is attached to a financial document
		c.project_id = p.project_id and	-- the cost is attached to a task
		main_p.tree_sortkey = tree_root_key(p.tree_sortkey); -- Get the main_project from any sub-level

	-- Pick a random senior manager who is not the supervisor
	select	max(gdmm.member_id), acs_object__name(max(gdmm.member_id))
	into	v_non_supervisor_id, v_non_supervisor_name
	from	group_distinct_member_map gdmm
	where	gdmm.group_id in (select group_id from groups where group_name = 'Senior Managers') and
		gdmm.member_id != v_supervisor_id; -- !!! What if supervisor is NULL???
	RAISE NOTICE 'The non-supervisor for % is % and called %', v_object_id, v_non_supervisor_id, v_non_supervisor_name;


	IF v_non_supervisor_id is not null THEN
		v_journal_id := journal_entry__new(
			null, v_case_id,
			v_transition_key || ' assign_to_non_supervisor ' || v_non_supervisor_name,
			v_transition_key || ' assign_to_non_supervisor ' || v_non_supervisor_name,
			now(), v_creation_user, v_creation_ip,
			'Assigning to user' || v_non_supervisor_name || ', the non_supervisor of ' ||
			acs_object__name(v_object_id) || '.'
		);
		PERFORM workflow_case__add_task_assignment(p_task_id, v_non_supervisor_id, 'f');
		PERFORM workflow_case__notify_assignee (p_task_id, v_non_supervisor_id, null, null,
			'wf_' || v_object_type || '_assignment_notif');
	ELSE	
		-- IF the non_supervisor_id is NULL, then we will get 'stuck' workflows.
		-- However, these WFs are shown to the admin who can fix them.
		v_journal_id := journal_entry__new(
			null, v_case_id,
			v_transition_key || ' assign_to_non_supervisor ' || v_non_supervisor_name,
			v_transition_key || ' assign_to_non_supervisor ' || v_non_supervisor_name,
			now(), v_creation_user, v_creation_ip,
			'NOT assigning to any user, because there is no non_supervisor_id for project ' ||
			acs_object__name(v_object_id) || ' with supervisor ' || v_supervisor_name || '.'
		);
	END IF;

	return 0;
END; $BODY$ LANGUAGE 'plpgsql' VOLATILE;




create or replace function im_workflow__assign_to_project_admins (integer, text)
returns integer as $$
declare
	p_task_id		alias for $1;
	p_custom_arg		alias for $2;

	v_case_id		integer;
	v_creation_ip		varchar;
	v_creation_user		integer;
	v_object_id		integer;
	v_object_type		varchar;
	v_journal_id		integer;
	v_transition_key	varchar;
	v_workflow_key		varchar;

	row			RECORD;
begin
	-- Select out some frequently used variables of the environment
	select	tr.transition_key, t.case_id, c.object_id, o.creation_user, o.creation_ip, o.object_type
	into	v_transition_key, v_case_id, v_object_id, v_creation_user, v_creation_ip, v_object_type
	from	wf_tasks t, wf_cases c, wf_transitions tr, acs_objects o
	where	t.task_id = p_task_id
		and t.case_id = c.case_id
		and o.object_id = t.case_id
		and t.workflow_key = tr.workflow_key
		and t.transition_key = tr.transition_key;

	RAISE NOTICE 'im_workflow__assign_to_project_admins: object_id=%, case_id=%', v_object_id, v_case_id;
	FOR row IN
		select  r.object_id_two as user_id,
			im_name_from_user_id(r.object_id_two) as user_name
		from	acs_rels r,
			im_biz_object_members bom
		where   r.object_id_one = v_object_id and
			r.rel_id = bom.rel_id and
			bom.object_role_id in (1301,1302)
	LOOP
		RAISE NOTICE 'im_workflow__assign_to_project_admins: object_id=%, case_id=%, assignee_id=%', v_object_id, v_case_id, row.user_id;
		v_journal_id := journal_entry__new(
		    null, v_case_id,
		    v_transition_key || ' assign_to_user ' || row.user_name,
		    v_transition_key || ' assign_to_user ' || row.user_name,
		    now(), v_creation_user, v_creation_ip,
		    'Assigning to ' || row.user_name
		);
		PERFORM workflow_case__add_task_assignment(p_task_id, row.user_id, 'f');
		PERFORM workflow_case__notify_assignee (p_task_id, row.user_id, null, null,
			'wf_' || v_object_type || '_assignment_notif');
	END LOOP;

	return 0;
end;$$ language 'plpgsql';
















-- Send out notification emails to assignees of workflow transitions
create or replace function workflow_case__notify_assignee (integer,integer,varchar,varchar,varchar)
returns integer as $$
declare
	notify_assignee__task_id		alias for $1;
	notify_assignee__user_id		alias for $2;
	notify_assignee__callback		alias for $3;
	notify_assignee__custom_arg		alias for $4;
	notify_assignee__notification_type	alias for $5;

	v_deadline_pretty			varchar;  
	v_object_name				text; 
	v_workflow_key				varchar;
	v_transition_key			wf_transitions.transition_key%TYPE;
	v_transition_name			wf_transitions.transition_name%TYPE;
	v_party_from				parties.party_id%TYPE;
	v_party_to				parties.party_id%TYPE;
	v_subject				text; 
	v_body					text; 
	v_request_id				integer; 
	v_workflow_url				text;
	v_acs_lang_package_id			integer;
	v_notifications_installed_p		integer;

	v_custom_arg				varchar;
	v_notification_type			varchar;
	v_notification_type_id			integer;
	v_workflow_package_id			integer;
	v_notification_n_seconds		integer;
	v_locale				text;
	v_impl_id				integer;
	v_str					varchar;
	v_user_first_names			varchar;
	v_user_last_name			varchar;
begin
	-- Default notification type
	v_notification_type := notify_assignee__notification_type;
	IF v_notification_type is null THEN
		v_notification_type := 'wf_assignment_notif';
	END IF;

	-- Get information about the workflow context into variables
	select	to_char(ta.deadline,'Mon fmDDfm, YYYY HH24:MI:SS'),
		acs_object__name(c.object_id), ta.workflow_key, tr.transition_key, tr.transition_name
	into	v_deadline_pretty, v_object_name, v_workflow_key, v_transition_key, v_transition_name
	from	wf_tasks ta, wf_transitions tr, wf_cases c
	where	ta.task_id = notify_assignee__task_id and
		c.case_id = ta.case_id and
		tr.workflow_key = c.workflow_key and
		tr.transition_key = ta.transition_key;

	select	a.package_id, apm__get_value(p.package_id, 'SystemURL') || site_node__url(s.node_id)
	into	v_workflow_package_id, v_workflow_url
	from	site_nodes s, apm_packages a,
		(select package_id
		from apm_packages 
		where package_key = 'acs-kernel') p
	where	s.object_id = a.package_id and
		a.package_key = 'acs-workflow';
	v_workflow_url := v_workflow_url || 'task?task_id=' || notify_assignee__task_id;

	select	pe.first_names, pe.last_name
	into	v_user_first_names, v_user_last_name
	from	persons pe
	where	pe.person_id = notify_assignee__user_id;
	RAISE NOTICE 'workflow_case__notify_assignee: task_id=%, user_id=%, obj=%, wf=%, trans=%',
	      notify_assignee__task_id, notify_assignee__user_id, v_object_name, v_workflow_key, v_transition_key;

	select	wfi.principal_party 
	into	v_party_from
	from	wf_context_workflow_info wfi, wf_tasks ta, wf_cases c
	where	ta.task_id = notify_assignee__task_id and
		c.case_id = ta.case_id and 
		wfi.workflow_key = c.workflow_key and
		wfi.context_key = c.context_key;
	if NOT FOUND then v_party_from := -1; end if;

	-- Check whether the "notifications" package is installed and get
	-- the notification interval of the user.
	select	count(*) into v_notifications_installed_p 
	from	user_tab_columns
	where	lower(table_name) = 'notifications';
	IF v_notifications_installed_p > 0 THEN

		-- Notification Type is a kind of "channel" where to spread notifics
		select	type_id into v_notification_type_id
		from	notification_types
		where	short_name = v_notification_type;

		-- Skip notification if there are no notification type defined
		IF v_notification_type_id is null THEN 
			RAISE WARNING 'workflow_case__notify_assignee: No notification channel found for % - creating a new one.', v_notification_type;

			v_impl_id := acs_sc_impl__new (
				'NotificationType',
				v_notification_type,
				'jobs'
			);

			v_notification_type_id := notification_type__new (
				NULL,
				v_impl_id,
				v_notification_type,
				'Wf ' || v_notification_type,
				'Workflow notifications for ' || v_notification_type,
				now(), NULL, NULL, NULL
			);
			
			-- enable the various intervals and delivery methods
			insert into notification_types_intervals (type_id, interval_id)
			select v_notification_type_id, interval_id
			from notification_intervals where name in ('instant','hourly','daily');

			insert into notification_types_del_methods (type_id, delivery_method_id)
			select v_notification_type_id, delivery_method_id
			from notification_delivery_methods where short_name in ('email');

		END IF;

		-- Check if the user is "subscribed" to these notifications
		select	n_seconds into v_notification_n_seconds
		from	notification_requests r,
			notification_intervals i
		where	r.interval_id = i.interval_id
			and user_id = notify_assignee__user_id
			and object_id = v_workflow_package_id
			and type_id = v_notification_type_id;

		-- Skip notification if there are no notifications defined
		IF v_notification_n_seconds is null THEN 
			RAISE NOTICE 'workflow_case__notify_assignee: User #%s is not subscribed to notification channel %.', 
			      notify_assignee__user_id, v_notification_type;
			return 0;
		END IF;

	END IF;


	-- Get the System Locale
	select	package_id into	v_acs_lang_package_id
	from	apm_packages
	where	package_key = 'acs-lang';
	v_locale := apm__get_value(v_acs_lang_package_id, 'SiteWideLocale');

	-- make sure there are no null values - replaces(...,null) returns null...
	IF v_deadline_pretty is NULL THEN v_deadline_pretty := 'undefined'; END IF;
	IF v_workflow_url is NULL THEN v_workflow_url := 'undefined'; END IF;

	-- ------------------------------------------------------------
	-- Lookup message and substitute
	v_subject := workflow_case__notify_l10n_lookup ('Notification_Subject', v_notification_type, v_workflow_key, v_transition_key, v_locale, 0);
	v_subject := replace(v_subject, '%object_name%', v_object_name);
	v_subject := replace(v_subject, '%transition_name%', v_transition_name);
	v_subject := replace(v_subject, '%deadline%', v_deadline_pretty);

	v_body := workflow_case__notify_l10n_lookup ('Notification_Body', v_notification_type, v_workflow_key, v_transition_key, v_locale, 1);
	v_body := replace(v_body, '%deadline%', v_deadline_pretty);
	v_body := replace(v_body, '%object_name%', v_object_name);
	v_body := replace(v_body, '%transition_name%', v_transition_name);
	v_body := replace(v_body, '%workflow_url%', v_workflow_url);
	v_body := replace(v_body, '%first_names%', v_user_first_names);
	v_body := replace(v_body, '%last_name%', v_user_first_names);

	RAISE NOTICE 'workflow_case__notify_assignee: Subject=%, Body=%', v_subject, v_body;

	v_custom_arg := notify_assignee__custom_arg;
	IF v_custom_arg is null THEN v_custom_arg := 'null'; END IF;

	if notify_assignee__callback != '' and notify_assignee__callback is not null then
		v_str := 'select ' || notify_assignee__callback || ' (' ||
			notify_assignee__task_id || ',' ||
			quote_literal(v_custom_arg) || ',' ||
			notify_assignee__user_id || ',' ||
			v_party_from || ',' ||
			quote_literal(v_subject) || ',' ||
			quote_literal(v_body) || ')';
		execute v_str;
	else
		v_request_id := acs_mail_nt__post_request (
			v_party_from,				-- party_from
			notify_assignee__user_id,		-- party_to
			'f',					-- expand_group
			v_subject,				-- subject
			v_body,					-- message
			0					-- max_retries
		);
	end if;

	return 0; 
end;$$ language 'plpgsql';



-- Unassigned callback for a financial document to assign a random senior manager who is not the project supervisor
CREATE OR REPLACE FUNCTION im_workflow__assign_to_findoc_project_financial_supervisor(integer, text)
RETURNS integer AS $BODY$
DECLARE
	p_task_id		alias for $1;
	p_custom_arg		alias for $2;
	v_transition_key	varchar;
	v_object_type		varchar;
	v_case_id		integer;
	v_object_id		integer;
	v_creation_user		integer;
	v_creation_ip		varchar;
	v_financial_supervisor_id 	integer;
	v_financial_supervisor_name	varchar;
	v_journal_id		integer;
BEGIN
	-- Get information about the transition and the 'environment'
	select	tr.transition_key, t.case_id, c.object_id, o.creation_user, o.creation_ip, o.object_type
	into	v_transition_key, v_case_id, v_object_id, v_creation_user, v_creation_ip, v_object_type
	from	wf_tasks t, wf_cases c, wf_transitions tr, acs_objects o
	where	t.task_id = p_task_id and
		t.case_id = c.case_id and
		o.object_id = t.case_id and
		t.workflow_key = tr.workflow_key and
		t.transition_key = tr.transition_key;

	-- From the financial document get the task and from there get
	-- the main_projects and extract its financial_supervisor_id
	select	main_p.cosine_financial_supervisor_id, im_name_from_id(main_p.cosine_financial_supervisor_id)
	into	v_financial_supervisor_id, v_financial_supervisor_name -- take the financial supervisor from the main project
	from	im_costs c,
		im_projects p,
		im_projects main_p
	where	c.cost_id = v_object_id and	-- the WF is attached to a financial document
		c.project_id = p.project_id and	-- the cost is attached to a task
		main_p.tree_sortkey = tree_root_key(p.tree_sortkey); -- Get the main_project from any sub-level

	IF v_financial_supervisor_id is not null THEN
		RAISE NOTICE 'The financial supervisor for % is % and called %', v_object_id, v_financial_supervisor_id, v_financial_supervisor_name;
		v_journal_id := journal_entry__new(
			null, v_case_id,
			v_transition_key || ' assign_to_financial_supervisor ' || v_financial_supervisor_name,
			v_transition_key || ' assign_to_financial_supervisor ' || v_financial_supervisor_name,
			now(), v_creation_user, v_creation_ip,
			'Assigning to user' || v_financial_supervisor_name || ', the financial supervisor of ' ||
			acs_object__name(v_object_id) || '.'
		);
	ELSE	
		RAISE NOTICE 'Missing financial supervisor for % - assigning to Senior Managers', v_object_id;
		select group_id, group_name into v_financial_supervisor_id, v_financial_supervisor_name
		from groups where group_name = 'Senior Managers';
		v_journal_id := journal_entry__new(
			null, v_case_id,
			v_transition_key || ' assign_to_senior_managers ' || v_financial_supervisor_name,
			v_transition_key || ' assign_to_senior_managers ' || v_financial_supervisor_name,
			now(), v_creation_user, v_creation_ip,
			'Assigning to Senior Managers, because there is no cosine_financial_supervisor_id for project ' ||
			acs_object__name(v_object_id) || '.'
		);
	END IF;
	PERFORM workflow_case__add_task_assignment(p_task_id, v_financial_supervisor_id, 'f');
	PERFORM workflow_case__notify_assignee (p_task_id, v_financial_supervisor_id, null, null, 'wf_' || v_object_type || '_assignment_notif');

	return 0;
END; $BODY$ LANGUAGE 'plpgsql' VOLATILE;

