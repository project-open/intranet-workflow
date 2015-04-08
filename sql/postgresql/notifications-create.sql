-- /packages/intranet-workflow/sql/postgres/intranet-workflow-create.sql
--
-- Copyright (c) 2003-2007 ]project-open[
--
-- All rights reserved. Please check
-- http://www.project-open.com/license/ for details.
--
-- @author frank.bergmann@project-open.com

create function inline_0() 
returns integer as $$
declare
	v_impl_id			integer;
	v_notif_type_id			integer;
	v_count				integer;
begin
	-- the notification type impl
	select count(*) into v_count from acs_sc_impls where impl_name = 'wf_assignment_notif_type';
	IF v_count = 0 THEN
		v_impl_id := acs_sc_impl__new (
		      'NotificationType',
		      'wf_assignment_notif_type',
		      'jobs'
		);
	END IF;

	select count(*) into v_count from acs_sc_impl_aliases 
	where impl_name = 'wf_assignment_notif_type';
	IF v_count = 0 THEN
		PERFORM acs_sc_impl_alias__new (
		    'NotificationType',
		    'wf_assignment_notif_type',
		    'GetURL',
		    'im_ticket::notification::get_url',
		    'TCL'
		);
		PERFORM acs_sc_impl_alias__new (
		    'NotificationType',
		    'wf_assignment_notif_type',
		    'ProcessReply',
		    'im_ticket::notification::process_reply',
		    'TCL'
		);
	END IF;


	PERFORM acs_sc_binding__new (
		'NotificationType',
		'wf_assignment_notif_type'
	);

	IF v_impl_id is not null THEN
	   	v_notif_type_id := notification_type__new (
			NULL,
			v_impl_id,
			'wf_assignment_notif',
			'WF Assignments',
			'Workflow assignments',
			now(),
			NULL,
			NULL,
			NULL
		);
	END IF;

        -- enable the various intervals and delivery methods
	IF v_notif_type_id is not null THEN
		insert into notification_types_intervals (type_id, interval_id)
		select v_notif_type_id, interval_id
		from notification_intervals where name in ('instant','hourly','daily');

		insert into notification_types_del_methods (type_id, delivery_method_id)
		select v_notif_type_id, delivery_method_id
		from notification_delivery_methods where short_name in ('email');
	END IF;

	return 0;
end;$$ language 'plpgsql';
select inline_0();
drop function inline_0();


-- Subscribe everybody
create or replace function inline_0() 
returns integer as $$
declare
	v_notification_type_id		integer;
	v_request_id			integer;
	v_wf_package_id			integer;
	v_notification_interval_id	integer;
	v_notification_delivery_id	integer;
	v_exists_p			integer;
	row				record;
begin
	select	type_id into v_notification_type_id from notification_types where short_name = 'wf_assignment_notif';
	select	package_id into v_wf_package_id from apm_packages where package_key = 'acs-workflow';
	select	interval_id into v_notification_interval_id from notification_intervals where name = 'instant';
	select	delivery_method_id into v_notification_delivery_id from notification_delivery_methods where short_name = 'email';

	FOR row IN
	    	select	user_id
		from	users
		where	user_id > 0
	LOOP
		select	count(*) into v_exists_p
		from	notification_requests
		where	type_id = v_notification_type_id and user_id = row.user_id;

		IF v_exists_p = 0 THEN
			v_request_id := notification_request__new(
				NULL,
				'notification_request',
				v_notification_type_id,
				row.user_id,
				v_wf_package_id,
				v_notification_interval_id,
				v_notification_delivery_id,
				'text',
				'f',
				now(), 0, '0.0.0.0', NULL
			);
		END IF;
	END LOOP;
	return 0;
end;$$ language 'plpgsql';
select inline_0();
drop function inline_0();
-- select * from notification_requests where type_id = 173221;
