-- /packages/intranet-workflow/sql/oracle/intranet-workflow-create.sql
--
-- Copyright (c) 2003-2004 Project/Open
--
-- All rights reserved. Please check
-- http://www.project-open.com/license/ for details.
--
-- @author frank.bergmann@project-open.com




-- ------------------------------------------------------
-- Update Project/Task types with Workflow types
-- ------------------------------------------------------

update im_categories
set category_description = 'trans_edit_wf'
where category_id = 87;

update im_categories
set category_description = 'edit_only_wf'
where category_id = 88;

update im_categories
set category_description = 'trans_edit_proof_wf'
where category_id = 89;

update im_categories
set category_description = 'localization_wf'
where category_id = 91;

update im_categories
set category_description = 'trans_only_wf'
where category_id = 93;

update im_categories
set category_description = 'trans_spotcheck_wf'
where category_id = 94;

update im_categories
set category_description = 'proof_only_wf'
where category_id = 95;

update im_categories
set category_description = 'glossary_compilation_wf'
where category_id = 96;



-- ------------------------------------------------------
-- Cleanup
-- ------------------------------------------------------

-- delete potentially existing menus and plugins if this
-- file is sourced multiple times during development...

select im_component_plugin__del_module('intranet-workflow');
select im_menu__del_module('intranet-workflow');



-- ------------------------------------------------------
-- Components
-- ------------------------------------------------------


-- Show the workflow component in project page
--
SELECT im_component_plugin__new (
        null,                           -- plugin_id
        'acs_object',                   -- object_type
        now(),                          -- creation_date
        null,                           -- creation_user
        null,                           -- creation_ip
        null,                           -- context_id
        'Home Workflow Component',      -- plugin_name
        'intranet-workflow',            -- package_name
        'left',                         -- location
        '/intranet/index',              -- page_url
        null,                           -- view_name
        1,                              -- sort_order
	'im_workflow_home_component'
);



-- ------------------------------------------------------
-- Menus
-- ------------------------------------------------------

create or replace function inline_0 ()
returns integer as '
declare
        -- Menu IDs
        v_menu                  integer;
        v_main_menu             integer;

        -- Groups
        v_employees             integer;
        v_accounting            integer;
        v_senman                integer;
        v_companies             integer;
        v_freelancers           integer;
        v_proman                integer;
        v_admins                integer;
        v_reg_users             integer;
BEGIN
    select group_id into v_admins from groups where group_name = ''P/O Admins'';
    select group_id into v_senman from groups where group_name = ''Senior Managers'';
    select group_id into v_proman from groups where group_name = ''Project Managers'';
    select group_id into v_accounting from groups where group_name = ''Accounting'';
    select group_id into v_employees from groups where group_name = ''Employees'';
    select group_id into v_companies from groups where group_name = ''Customers'';
    select group_id into v_freelancers from groups where group_name = ''Freelancers'';
    select group_id into v_reg_users from groups where group_name = ''Registered Users'';

    select menu_id
    into v_main_menu
    from im_menus
    where label=''main'';

    v_menu := im_menu__new (
        null,                   -- p_menu_id
        ''acs_object'',         -- object_type
        now(),                  -- creation_date
        null,                   -- creation_user
        null,                   -- creation_ip
        null,                   -- context_id
        ''intranet-workflow'',  -- package_name
        ''workflow'',           -- label
        ''Workflow'',           -- name
        ''/intranet-workflow/'',-- url
        50,                     -- sort_order
        v_main_menu,            -- parent_menu_id
        null                    -- p_visible_tcl
    );

    PERFORM acs_permission__grant_permission(v_menu, v_admins, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_senman, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_proman, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_accounting, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_employees, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_companies, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_freelancers, ''read'');

    return 0;
end;' language 'plpgsql';

select inline_0 ();

drop function inline_0 ();



