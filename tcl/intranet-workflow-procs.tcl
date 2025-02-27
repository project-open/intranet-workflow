# /packages/intranet-workflow/tcl/intranet-workflow-procs.tcl
#
# Copyright (C) 2003-2008 ]project-open[
#
# All rights reserved. Please check
# https://www.project-open.com/license/ for details.

ad_library {
    @author frank.bergmann@project-open.com
}


# ----------------------------------------------------------------------
# 
# ----------------------------------------------------------------------

ad_proc -public im_package_workflow_id {} {
    Returns the package id of the intranet-workflow module
} {
    return [util_memoize im_package_workflow_id_helper]
}

ad_proc -private im_package_workflow_id_helper {} {
    return [db_string im_package_core_id {
        select package_id from apm_packages
        where package_key = 'intranet-workflow'
    } -default 0]
}

ad_proc -private im_workflow_url {} {
    returns "workflow" or "acs-workflow", depending where the
    acs-workflow module has been mounted.
} {
    set urls [util_memoize [list db_list urls "select n.name from site_nodes n, apm_packages p where n.object_id = p.package_id and package_key = 'acs-workflow'"]]
    return [lindex $urls 0]
}


# ----------------------------------------------------------------------
# Aux
# ---------------------------------------------------------------------

ad_proc -public im_workflow_replace_translations_in_string { 
    {-translate_p 1}
    {-locale ""}
    str 
} {
    if {"" == $locale} { set locale [lang::user::locale -user_id [ad_conn user_id]] }
    return [util_memoize [list im_workflow_replace_translations_in_string_helper -translate_p $translate_p -locale $locale $str]]
}

ad_proc -public im_workflow_replace_translations_in_string_helper { 
    {-translate_p 1}
    {-locale ""}
    str 
} {
    # Replace #...# expressions in assignees_pretty with translated version
    set cnt 0
    while {$cnt < 100 && [regexp {^(.*?)#([a-zA-Z0-9_\.\-]*?)#(.*)$} $str match pre trans post]} {
	set str "$pre[lang::message::lookup $locale $trans "'$trans'"]$post"
	incr cnt
    }
    return $str
}


# ----------------------------------------------------------------------
# Start a WF for an object
# ---------------------------------------------------------------------

ad_proc -public im_workflow_start_wf {
    -object_id
    {-object_type_id ""}
    {-workflow_key ""}
    {-skip_first_transition_p 0}
} {
    Start a new WF for an object.
} {
    if {"" eq $workflow_key} {
	set workflow_key [db_string wf "select aux_string1 from im_categories where category_id = :object_type_id" -default ""]
    }

    set wf_exists_p [db_string wf_exists "select count(*) from wf_workflows where workflow_key = :workflow_key"]
    set case_id 0

    if {$wf_exists_p} {
	set context_key ""
	set case_id [wf_case_new \
			 $workflow_key \
			 $context_key \
			 $object_id
		    ]
	
	# Determine the first task in the case to be executed and start+finisch the task.
	if {1 == $skip_first_transition_p} {
	    im_workflow_skip_first_transition -case_id $case_id
	}
    }
    im_audit -object_id $object_id

    return $case_id
}

# ----------------------------------------------------------------------
# Selects & Options
# ---------------------------------------------------------------------

ad_proc -public im_workflow_list_options {
    {-include_empty 0}
    {-min_case_count 0}
    {-translate_p 0}
    {-locale ""}
} {
    Returns a list of workflows that satisfy certain conditions
} {
    set min_count_where ""
    if {$min_case_count > 0} { set min_count_where "and count(c.case_id) > 0\n" }
    set options [db_list_of_lists project_options "
	 select
		t.pretty_name,
		w.workflow_key,
		count(c.case_id) as num_cases,
		0 as num_unassigned_tasks
	 from   wf_workflows w left outer join wf_cases c
		  on (w.workflow_key = c.workflow_key and c.state = 'active'),
		acs_object_types t
	 where  w.workflow_key = t.object_type
		$min_count_where
	 group  by w.workflow_key, t.pretty_name
	 order  by t.pretty_name
    "]
    if {$include_empty} { set options [linsert $options "" { "" "" }] }
    return $options
}


ad_proc -public im_workflow_pretty_name {
    workflow_key
} {
    Returns a pretty name for the WF
} {
    if {![regexp {^[a-z0-9_]*$} $workflow_key match]} {
        im_security_alert -location im_workflow_pretty_name -message "SQL Injection Attempt" -value $workflow_key -severity "Severe"
	return "$workflow_key"
    }
    return [util_memoize [list db_string pretty_name "select pretty_name from acs_object_types where object_type = '$workflow_key'" -default $workflow_key]]
}


ad_proc -public im_workflow_status_options {
    {-translate_p 0}
    {-locale ""}
    {-include_empty 1}
    {-include_empty_name ""}
    workflow_key
} {
    Returns a list of stati (actually: Places) 
    for the given workflow
} {
    set options [db_list_of_lists project_options "
	 select	place_key,
		place_key
	from	wf_places wfp
	where	workflow_key = :workflow_key
    "]
    if {$include_empty} { set options [linsert $options 0 [list $include_empty_name "" ]] }
    return $options
}

ad_proc -public im_workflow_status_select { 
    {-include_empty 1}
    {-include_empty_name ""}
    {-translate_p 0}
    {-locale ""}
    workflow_key
    select_name
    { default "" }
} {
    Returns an html select box named $select_name and defaulted to
    $default with a list of all the project_types in the system
} {
    if {"" == $workflow_key} {
	ad_return_complaint 1 "im_workflow_status_select:<br>
        Found an empty workflow_key. Please inform your SysAdmin."
        return
    }

    set options [im_workflow_status_options \
	-include_empty $include_empty \
	-include_empty_name $include_empty_name \
	$workflow_key \
    ]

    set result "<select name=\"$select_name\">"
    foreach option $options {
	set value [lindex $option 0]
	set key [lindex $option 1]
	set selected ""
	if {$default eq $key} { set selected "selected" }
        append result "<option value=\"$key\" $selected>$value</option>\n"
    }
    append result "</select>\n"
    return $result
}


# ----------------------------------------------------------------------
# Check if the workflow is stuck with an unassigned task
# ---------------------------------------------------------------------

ad_proc -public im_workflow_stuck_p {
} {
    Checks whether the workflow is "stuck".
    That means: If all of the currently enabled tasks are
    unassigned.
} {
    return 0
}




# ----------------------------------------------------------------------
# Workflow Task List Component
# ---------------------------------------------------------------------

ad_proc -public im_workflow_home_component {
} {
    Creates a HTML table showing all currently active tasks
} {
    set user_id [ad_conn user_id]
    set admin_p [permission::permission_p -object_id [ad_conn package_id] -privilege "admin"]

    set template_file "packages/acs-workflow/www/task-list"
    set template_path [get_server_root]/$template_file
    set template_path [ns_normalizepath $template_path]

    set package_url "/[im_workflow_url]/"

    set own_tasks [template::adp_parse $template_path [list package_url $package_url type own]]
    set own_tasks "<h3>[lang::message::lookup "" intranet-workflow.Your_Tasks "Your Tasks"]</h3>\n$own_tasks"

    set all_tasks [template::adp_parse $template_path [list package_url $package_url]]
    set all_tasks "<h3>[lang::message::lookup "" intranet-workflow.All_Tasks "All Tasks"]</h3>\n$all_tasks"
    # Disable the "All Tasks" if it doesn't contain any lines.
    if {![regexp {<tr>} $all_tasks match]} { set all_tasks ""}

    set unassigned_tasks ""
    if {$admin_p} {
	set unassigned_tasks [template::adp_parse $template_path [list package_url $package_url type unassigned]]
	set unassigned_tasks "<h3>[lang::message::lookup "" intranet-workflow.Unassigned_Tasks "Unassigned Tasks"]</h3>\n$unassigned_tasks"
    }

    set component_html "
<table class=\"table_container\">
<tr><td>
$own_tasks
$all_tasks
$unassigned_tasks
</td></tr>
</table>
<br>
"

    return $component_html
}



# ----------------------------------------------------------------------
# Graph Procedures
# ---------------------------------------------------------------------



ad_proc -public im_workflow_graph_sort_order {
    workflow_key
} {
    Update the "sort_order" field in wf_transitions
    in order to reflect their distance from "start",
    including places like nodes.
} {
    set arc_sql "
	select *
	from wf_arcs
	where workflow_key = :workflow_key
    "
    db_foreach arcs $arc_sql {
	set distance($place_key) 9999999999
	set distance($transition_key) 9999999999
	switch $direction {
	    in { lappend edges [list $place_key $transition_key] }
	    out { lappend edges [list $transition_key $place_key] }
	}
    }
    
    # Do a breadth-first search trought the graph and search for
    # the shortest path from "start" to the respective node.
    set active_nodes [list start]
    set distance(start) 0
    set cnt 0
    while {[llength $active_nodes] > 0} {
	incr cnt
	ns_log Notice "im_workflow_graph_sort_order: cnt=$cnt, active_nodes=$active_nodes"
	if {$cnt > 10000} {
	    ad_return_complaint 1 "Workflow:<br>
	    Infinite loop in im_workflow_graph_sort_order. <br>
	    Please contact your system administrator"
	    return
	}

	# Extract the first node from active nodes
	set active_node [lindex $active_nodes 0]
	set active_nodes [lrange $active_nodes 1 end]
	foreach edge $edges {
	    set from [lindex $edge 0]
	    set to [lindex $edge 1]
	    # Check if we find and outgoing edge from node
	    if {$from eq $active_node} {
		set dist1 [expr {$distance($from) + 1}]
		if {$dist1 < $distance($to)} {
		    set distance($to) $dist1
		    ns_log Notice "im_workflow_graph_sort_order: distance($to) = $dist1"

		    # Updating here might be a bit slower then after the loop
		    # (some duplicate updates possible), but is very convenient...
		    db_dml update_distance "
			update wf_transitions
			set sort_order = :dist1
			where
				workflow_key = :workflow_key
				and transition_key = :to
		    "

		    # Append the new to-node to the end of the active nodes.
		    lappend active_nodes $to
		}
	    }
	}
    }
}


# ----------------------------------------------------------------------
# Adapters to show WF components
# ---------------------------------------------------------------------

ad_proc -public im_workflow_graph_component {
    -object_id:required
} {
    Show a Graphical WF representation of a workflow associated
    with an object.
} {
    set user_id [ad_conn user_id]
    set user_is_admin_p [im_is_user_site_wide_or_intranet_admin $user_id]
    set subsite_id [ad_conn subsite_id]
    set reassign_p [permission::permission_p -party_id $user_id -object_id $subsite_id -privilege "wf_reassign_tasks"]
    set size [parameter::get_from_package_key -package_key "intranet-workflow" -parameter "WorkflowComponentWFGraphSize" -default "5,5"]
    set bgcolor(0) " class=roweven "
    set bgcolor(1) " class=rowodd "
    set date_format "YYYY-MM-DD"
    set return_url [im_url_with_query]

    # ---------------------------------------------------------------------
    # Check if there is a WF case with object_id as reference object
    # Do the case_ids query _before_ the foreach to avoid nesting SQLs.
    set case_ids [db_list case_ids "select case_id from wf_cases where object_id = :object_id order by case_id"]
    if {0 == [llength $case_ids]} { return "" }

    set result_html ""
    foreach case_id $case_ids {

	# ---------------------------------------------------------------------
	# WF graph component
	db_1row workflow_info "
		select	*,
			wfc.state as case_state
		from	wf_workflows wfw,
			wf_cases wfc
		where	wfc.case_id = :case_id and
			wfw.workflow_key = wfc.workflow_key
	"

	set params [list [list case_id $case_id] [list size $size]]
	set graph_html [ad_parse_template -params $params "/packages/acs-workflow/www/case-state-graph"]

	# ---------------------------------------------------------------------
	# Who has been acting on the WF until now?
	set history_html ""
	set history_sql "
	select	t.*,
		tr.transition_name,
		to_char(coalesce(t.started_date, t.finished_date), :date_format) as started_date_pretty,
		to_char(t.finished_date, :date_format) as finished_date_pretty,
		im_name_from_user_id(t.holding_user) as holding_user_name
	from
		wf_transitions tr, 
		wf_tasks t
	where
		t.case_id = :case_id
		and t.state not in ('enabled', 'started')
		and tr.workflow_key = t.workflow_key
		and tr.transition_key = t.transition_key
		and trigger_type = 'user'
	order by t.enabled_date
	"
	set cnt 0
	db_foreach history $history_sql {
	    append history_html "
	    <tr $bgcolor([expr {$cnt % 2}])>
		<td>$transition_name</td>
		<td><nobr><a href=/intranet/users/view?user_id=$holding_user>$holding_user_name</a></nobr></td>
		<td><nobr>$started_date_pretty</nobr></td>
	    </tr>
	"
	    incr cnt
	}

	set history_html "
		<table class=\"table_list_page\">
		<tr class=rowtitle>
		  <td colspan=3 align=center class=rowtitle>[lang::message::lookup "" intranet-workflow.Past_actions "Past Actions"]</td>
		</tr>
		<tr class=rowtitle>
			<td class=rowtitle>[lang::message::lookup "" intranet-workflow.What "What"]</td>
			<td class=rowtitle>[lang::message::lookup "" intranet-workflow.Who "Who"]</td>
			<td class=rowtitle>[lang::message::lookup "" intranet-workflow.When "When"]</td>
		</tr>
		$history_html
		</table>
    "


	# ---------------------------------------------------------------------
	# Next Transition Information
	set transition_html ""
	set transition_sql "
	select	t.*,
		tr.*,
		to_char(t.started_date, :date_format) as started_date_pretty,
		to_char(t.finished_date, :date_format) as finished_date_pretty,
		im_name_from_user_id(t.holding_user) as holding_user_name,
		to_char(t.trigger_time, :date_format) as trigger_time_pretty
	from
		wf_transitions tr, 
		wf_tasks t
	where
		t.case_id = :case_id
		and t.state in ('enabled', 'started')
		and tr.workflow_key = t.workflow_key
		and tr.transition_key = t.transition_key
	order by t.enabled_date
    "
	set cnt 0
	db_foreach transition $transition_sql {
	    regsub -all " " $transition_name "_" next_action_key; # L10ned version of next action
	    set next_action_l10n [lang::message::lookup "" intranet-workflow.$next_action_key $transition_name]
	    set action_url [export_vars -base "/[im_workflow_url]/task" {return_url task_id}]
	    set action_link "<a class=button href=$action_url>$next_action_l10n</a>"

	    append transition_html "<table class=\"table_list_page\">\n"
	    append transition_html "<tr class=rowtitle><td colspan=2 class=rowtitle align=center>
		[lang::message::lookup "" intranet-workflow.Next_step_details "Next Step: Details"]
	</td></tr>\n"
	    append transition_html "<tr $bgcolor([expr {$cnt % 2}])><td>
		[lang::message::lookup "" intranet-workflow.Task "Task"]
	</td><td>$action_link</td></tr>\n"
	    incr cnt
	    append transition_html "<tr $bgcolor([expr {$cnt % 2}])><td>
		[lang::message::lookup "" intranet-workflow.Holding_user "Holding User"]
	</td><td>$holding_user_name</td></tr>\n"
	    incr cnt
	    append transition_html "<tr $bgcolor([expr {$cnt % 2}])><td>
		[lang::message::lookup "" intranet-workflow.Task_state "Task State"]
	</td><td>$state</td></tr>\n"
	    incr cnt

	    set ttt {
		append transition_html "<tr $bgcolor([expr {$cnt % 2}])><td>
		[lang::message::lookup "" intranet-workflow.Automatic_trigger "Automatic Trigger"]
	</td><td>$trigger_time_pretty</td></tr>\n"
		incr cnt
	    }

	    if {$reassign_p} {
		append transition_html "
		<tr class=rowplain><td colspan=2>
		<ul>
			<li><a href=[export_vars -base "/[im_workflow_url]/assign-yourself" {task_id return_url}]>[lang::message::lookup "" intranet-workflow.Assign_yourself "Assign yourself"]</a>
			<li><a href=[export_vars -base "/[im_workflow_url]/task-assignees" {task_id return_url}]>[lang::message::lookup "" intranet-workflow.Assign_somebody_else "Assign somebody else"]</a>
		</ul>
		</td></tr>
            "
	    }

	    append transition_html "</table>\n"
	}

	# ---------------------------------------------------------------------
	# Who is assigned to the current transition?
	set assignee_html ""
	set assignee_sql "
	select	t.*,
		t.holding_user,
		tr.transition_name,
		ta.party_id,
		acs_object__name(ta.party_id) as party_name,
		im_name_from_user_id(ta.party_id) as user_name,
		o.object_type as party_type
	from
		wf_transitions tr, 
		wf_tasks t,
		wf_task_assignments ta,
		acs_objects o
	where
		t.case_id = :case_id
		and t.state in ('enabled', 'started')
		and tr.workflow_key = t.workflow_key
		and tr.transition_key = t.transition_key
		and ta.task_id = t.task_id
		and ta.party_id = o.object_id
	order by t.enabled_date
        "
	set cnt 0
	db_foreach assignee $assignee_sql {
	    if {"user" == $party_type} { set party_name $user_name } 
	    if {$holding_user == $party_id} { set party_name "<b>$party_name</b>" }
	    set party_link "<a href=/intranet/users/view?user_id=$party_id>$party_name</a>"
	    if {"user" != $party_type} { set party_link $party_name	}
	    append assignee_html "
	    <tr $bgcolor([expr {$cnt % 2}])>
		<td>$transition_name</td>
		<td><nobr>$party_link</nobr></td>
	    </tr>
	"
	    incr cnt
	}
	if {0 == $cnt} {
	    append assignee_html "
	    <tr $bgcolor([expr {$cnt % 2}])>
		<td colspan=2><i>&nbsp;Nobody assigned</i></td>
	    </tr>
        "
	}

	set assignee_html "
		<table class=\"table_list_page\">
		<tr class=rowtitle>
		  <td colspan=2 align=center class=rowtitle
		  >[lang::message::lookup "" intranet-workflow.Current_assignees "Current Assignees"]</td>
		</tr>
		<tr class=rowtitle>
			<td class=rowtitle>[lang::message::lookup "" intranet-workflow.What "What"]</td>
			<td class=rowtitle>[lang::message::lookup "" intranet-workflow.Who "Who"]</td>
		</tr>
		$assignee_html
        "
	if {$reassign_p} {

	    set debug_case_help "Show extended debug information"
	    set start_new_case_help "Create a new case of the same workflow and start it from scratch"
	    set nuke_case_help "Nuke this workflow from the database without a trace"
	    set cancel_case_help "Cancel this workflow. No further WF action will occur."
	    set restart_case_help "Restart this workflow from the start, maintaining the journal"

	    append assignee_html "
		<tr class=rowplain><td colspan=2>
		<ul>
		<li><a href='[export_vars -base "/[im_workflow_url]/case?" {case_id}]'>
                           [lang::message::lookup "" intranet-workflow.Debug_case "Debug case"]
			   [im_gif help $debug_case_help]
                </a>
		<li><a href='[export_vars -base "/intranet-workflow/reset-case?" {return_url case_id {action "cancel"} {action_pretty "Cancel"}}]'>
                           [lang::message::lookup "" intranet-workflow.Cancel_Case "Cancel case"]
			   [im_gif help $cancel_case_help]
                </a>
		<li><a href='[export_vars -base "/intranet-workflow/reset-case?" {return_url case_id {action "nuke"} {action_pretty "Nuke"}}]'>
                           [lang::message::lookup "" intranet-workflow.Nuke_Case "Nuke case"]
			   [im_gif help $nuke_case_help]
                </a>
		<li><a href='[export_vars -base "/intranet-workflow/reset-case?" {return_url case_id {action "restart"} {place_key "start"} {action_pretty "Restart"}}]'>
                           [lang::message::lookup "" intranet-workflow.Restart_Case "Restart case"]
			   [im_gif help $restart_case_help]
                </a>
		<li><a href='[export_vars -base "/intranet-workflow/reset-case?" {return_url case_id {action "copy"} {action_pretty "Copy"}}]'>
                           [lang::message::lookup "" intranet-workflow.Copy_Case "Copy and start new case"]
			   [im_gif help $start_new_case_help]
                </a>
		</ul>
		</td></tr>
        "
	}
	append assignee_html "</table>\n"

	set status_html "[_ intranet-core.Status]: $case_state"
	if {$case_state in {"created" "active"}} { set status_html "" }

	# This is the HTML for a single case
	set case_html "
	<table>
	<tr valign=top>
	<td>$graph_html</td>
	<td>
		<h3>[lang::message::lookup "" intranet-workflow.workflow_$workflow_key $workflow_key]</h3>
		<p>[_ intranet-core.Description]: $description</p>
		$status_html
		$history_html<br>
		$transition_html<br>
		$assignee_html
	</td>
	</tr>
	</table>
        "

	append result_html "<td valign=top>$case_html</td>\n"

    }

    # Return the workflows beside each other
    return "<table><tr>$result_html</tr></table>"
}



ad_proc -public im_workflow_action_component {
    -object_id:required
} {
    Shows WF default actions for the specified object, 
    or a user-defined action panel if configured in the WF.<p>

    There are 5 different cases to deal with:
	- Enable: The user needs to press the "Start" button to
	  take ownership of that task.
		a: The current user is in the assignee list
		b: The current user is not assigned to the task
	- Started: The task has been started:
		a: This is the user who started the case
		b: This is not the user who started the case
	- Canceled
	- Finished
} {
    set current_user_id [ad_conn user_id]
    set user_is_admin_p [im_is_user_site_wide_or_intranet_admin $current_user_id]
    set return_url [im_url_with_query]

    set bgcolor(0) " class=roweven "
    set bgcolor(1) " class=rowodd "

    # Get all "enabled" task for this object:
    set enabled_tasks [db_list enabled_tasks "
		select
			wft.task_id
		from    wf_tasks wft,
			wf_cases wfc
		where
			wfc.object_id = :object_id
			and wfc.case_id = wft.case_id
			and wft.state in ('enabled', 'started')
    "]

    set result ""
    set graph_html ""

    template::multirow create panels header template_url bgcolor
    foreach task_id $enabled_tasks {

	# Clean the array for the next task
	array unset task
	set export_vars [export_vars -form {task_id return_url}]

	# ---------------------------------------------------------
	# Get everything about the task

	if {[catch {
	    array set task [wf_task_info $task_id]
	} err_msg]} {
	    ad_return_complaint 1 "<li><b>[lang::message::lookup "" acs-workflow.Task_not_found "Task not found:"]</b><p>
	        [lang::message::lookup "" acs-workflow.Task_not_found_message "
                This error can occur if a system administrator has deleted a workflow.<br>
                This situation should not occur during normal operations.<p>
                Please contact your System Administrator"]
            "
	    return
	}

	set task(add_assignee_url) "/[im_workflow_url]/[export_vars -base assignee-add {task_id}]"
	set task(assign_yourself_url) "/[im_workflow_url]/[export_vars -base assign-yourself {task_id return_url}]"
	set task(manage_assignments_url) "/[im_workflow_url]/[export_vars -base task-assignees {task_id return_url}]"
	set task(cancel_url) "/[im_workflow_url]/[export_vars -base task {task_id return_url {action.cancel Cancel}}]"
	set task(action_url) "/[im_workflow_url]/task"
	set task(return_url) $return_url

	set context [list [list "/[im_workflow_url]/case?case_id=$task(case_id)" "$task(object_name) case"] "$task(task_name)"]
	set panel_color "#dddddd"
	set show_action_panel_p 1

	# ---------------------------------------------------------
	# Graph component
	set size [parameter::get_from_package_key -package_key "intranet-workflow" -parameter "ActionComponentWFGraphSize" -default "3,3"]
	set params [list [list case_id $task(case_id)] [list size $size]]
	set graph_html [ad_parse_template -params $params "/packages/acs-workflow/www/case-state-graph"]

	# ---------------------------------------------------------
	# Get action panel(s) for the task

	set override_action 0
	set this_user_is_assigned_p 1
	set action_panels_sql "
		select
			tp.header, 
			tp.template_url
		from
			wf_context_task_panels tp, 
			wf_cases c,
			wf_tasks t
		where
			t.task_id = :task_id
			and c.case_id = t.case_id
			and tp.context_key = c.context_key
			and tp.workflow_key = c.workflow_key
			and tp.transition_key = t.transition_key
			and (tp.only_display_when_started_p = 'f' or (t.state = 'started' and :this_user_is_assigned_p = 1))
			and tp.overrides_action_p = 't'
		order by tp.sort_order
        "
	set action_panel_count [db_string action_panel_count "select count(*) from ($action_panels_sql) t"]
	if {0 == $action_panel_count} {
	    set action_panels_sql "
		select	'Action' as header,
			'task-action' as template_url
	    "
	}

	set ctr 0
	db_foreach action_panels $action_panels_sql {

	    set task_actions {}

	    # --------------------------------------------------------------------
	    # Table header common to all states
	    append result "
				<form action='/[im_workflow_url]/task' method='post'>
				$export_vars
				<table>
		        	<tr $bgcolor([expr {$ctr%2}])>
		        	    <td>Task Name</td>
		        	    <td>$task(task_name)</td>
		        	</tr>
	    "
	    incr ctr

	    if {"" != [string trim $task(instructions)]} {
		append result "
		        	<tr $bgcolor([expr {$ctr%2}])>
		        	    <td>Task Description</td>
		        	    <td>$task(instructions)</td>
		        	</tr>
		"
		incr ctr
	    }

	    if {$user_is_admin_p} {
		append result "
		        	<tr $bgcolor([expr ($ctr+1)%2])>
		        	    <td>Task Status</td>
		        	    <td>$task(state)</td>
		        	</tr>
	        "
		incr ctr
	    }

	    switch $task(state) {

		enabled {
		    # --------------------------------------------------------------------
		    if {$task(this_user_is_assigned_p)} {
			append result "
				<tr class=rowodd>
					<td>Action</th>
					<td><input type='submit' name='action.start' value='Start task' /></td>
				</tr>
			"
		    } else {
			append result "
				<tr $bgcolor([expr {$ctr%2}])>
					<td>Action</td>
					<td>
					    This task has been assigned to somebody else.<br>
					    There is nothing to do for you right now.
					</td>
				</tr>				
			"
			incr ctr
		    }
		}


		started {
		    # --------------------------------------------------------------------

		    lappend task_actions "(<a href='$task(cancel_url)'>cancel task</a>)"

		    if {$task(this_user_is_assigned_p)} { 

			template::multirow foreach task_roles_to_assign {
			    append result "
		                <tr class=roweven>
		                    <td>Assign $role_name</td>
		                    <td>$assignment_widget</td>
		                </tr>
			    "
			}

			template::multirow foreach task_attributes_to_set {
			    append result "
		                <tr class=rowodd>
		                    <td>$pretty_name</td>
		                    <td>$attribute_widget</td>
		                </tr>
			    "
			}
			append result "
		             <tr class=rowodd>
		                 <td>Comment</td>
		                 <td><textarea name='msg' cols=20 rows=4></textarea></td>
		             </tr>
		             <tr class=roweven>
		                 <td>Action</td>
		                 <td>
		                     <input type='submit' name='action.finish' value='Task done' />
		                 </td>
		             </tr>
			"

			append result "
				<tr class=roweven>
					<td>Started</td>
					<td>$task(started_date_pretty)&nbsp; &nbsp; </td>
				</tr>
			"

		    } else {

			append result "
				    <tr><td>Held by</td><td><a href='/intranet/users/view?user_id=$task(holding_user)'>$task(holding_user_name)</a></td></tr>
				    <tr><td>Since</td><td>$task(started_date_pretty)</td></tr>
				    <tr><td>Timeout</td><td>$task(hold_timeout_pretty)</td></tr>
			"

		    }
		    
		}

		canceled {
		    if {$task(this_user_is_assigned_p)} { 
append result "You canceled this task on $task(canceled_date_pretty).<p><a href='$return_url'>Go back</a>" 
		    } else {
append result "This task has been canceled by <a href='/intranet/users/view?user_id=$task(holding_user)'>$task(holding_user_name)</a> on $task(canceled_date_pretty)"
		    }
		    
		}
		finished {
		    if {$task(this_user_is_assigned_p)} { 
append result "You finished this task on $task(finished_date_pretty).<p><a href='$return_url'>Go back</a>"
		    } else {
append result "This task was completed by <a href='/shared/community-member?user_id=$task(holding_user)'>$task(holding_user_name)</a>at $task(finished_date_pretty)"

		    }
		    
		}
	
		default {
		    append result "<p><font=red>Found task with invalid state '$task(state)'</font></p>"
		}
	
	    }
	    # end of switch


	    # --------------------------------------------------------------------
	    # Timeout
	    if {"" != $task(hold_timeout_pretty)} {
		set timeout_html "<td>Timeout</td><td>$task(hold_timeout_pretty)</td>\n"
		append result "
				<tr $bgcolor([expr {$ctr%2}])>
					$timeout_html
				</tr>
		"
		incr ctr
	    }

	    # --------------------------------------------------------------------
	    # Deadline
	    if {"" != [string trim $task(deadline_pretty)]} {
		if {$task(days_till_deadline) < 1} {
		    set deadline_html "<td>Deadline</td><td><font color='red'><strong>Deadline is $task(deadline_pretty)</strong></font></td>\n"
		} else {
		    set deadline_html "<td>Deadline</td><td>Deadline is $task(deadline_pretty)</td>\n"
		}
		append result "
				<tr $bgcolor([expr {$ctr%2}])>
					$deadline_html
				</tr>
		"
		incr ctr
	    }

	    # --------------------------------------------------------------------
	    # Assigned users
	    set assigned_users {}
	    if {[im_permission $current_user_id "wf_reassign_tasks"]} {
		template::multirow foreach task_assigned_users { 
		    set user_url [export_vars -base "/intranet/users/view" {user_id}]
		    lappend assigned_users "<a href='$user_url'><nobr>$name</nobr></a>\n"
		}
	    }
	    if {[llength $assigned_users] > 0} {
		append result "
				<tr $bgcolor([expr {$ctr%2}])>
					<td>Assigned Users</td>
					<td>[join $assigned_users "<br>\n"]</td>
				</tr>
		"
		incr ctr
	    }

	    # --------------------------------------------------------------------
	    # Extreme Actions
	    if {[im_permission $current_user_id "wf_reassign_tasks"]} {
		if {!$task(this_user_is_assigned_p)} {
		    lappend task_actions "(<a href='$task(assign_yourself_url)'>assign yourself</a>)"
		}
		lappend task_actions "(<a href='$task(manage_assignments_url)'>reassign task</a>)"
	    }

	    if {[llength $task_actions] > 0} {
		append result "
				<tr $bgcolor([expr {$ctr%2}])>
					<td>Extreme Actions</td>
					<td>[join $task_actions "&nbsp; \n"]</td>
				</tr>
		"
		incr ctr
	    }

	    # --------------------------------------------------------------------
	    # Close the table
	    append result "
			</table>
			</form>
	    "
	    
	}
    }
    if {"" == $result} {
	return "
		<table class=\"table_list_page\">
		<tr valign=top>
		<td>
			<b>[lang::message::lookup "" intranet-helpdesk.Workflow_Finished "Workflow Finished"]</b><br>
			[lang::message::lookup "" intranet-helpdesk.Workflow_Finished_msg "
				The workflow has finished and there are no more actions to take.
			"]
		</td>
		<td>$graph_html</td>
		</tr>
		</table>
	"
    }

    return "
	<table width='100%' >
	<tr valign=top>
	<td>$result</td>
	<td>$graph_html</td>
	</tr>
	</table>
    "
}

ad_proc -public im_workflow_journal_component {
    -object_id:required
} {
    Show the WF Journal for an object
} {
    # Check if there is a WF case with object_id as reference object
    set case_ids [db_list case "select case_id from wf_cases where object_id = :object_id order by case_id"]
    if {0 == [llength $case_ids]} { return "" }

    set result ""
    foreach case_id $case_ids {
	set params [list [list case_id $case_id]]
	append result [ad_parse_template -params $params "/packages/acs-workflow/www/journal"]
    }

    return $result
}

ad_proc -public im_workflow_new_journal {
    -case_id:required
    -action:required
    -action_pretty:required
    -message:required
} {
    Creates a new journal entry that can be passed to PL/SQL routines
} {
    set user_id [ad_conn user_id]
    set peer_ip [ad_conn peeraddr]

    set jid [db_string new_journal "
	select journal_entry__new (
		null,
		:case_id,
		:action,
		:action_pretty,
		now(),
		:user_id,
		:peer_ip,
		:message
	)
    "]
    return $jid
}

ad_proc -public im_workflow_replacing_vacation_users {
    {-user_id "" }
} {
    Returns the list of users that the current_user_id is replacing,
    including himself.
} {
    set current_user_id [ad_conn user_id]
    if {"" ne $user_id} { set current_user_id $user_id }

    # Vacation Absence Logic:
    # Check if the current user is the vacation replacement for some other user
    set replacement_ids [list $current_user_id]
    if {[im_column_exists im_user_absences vacation_replacement_id]} {
        # Get all the guys on vacation who have specified
	# that the current user (or one of it's groups)
	# should be the vacation replacement.
	set sql "
		select	a.owner_id
		from	im_user_absences a
		where	a.vacation_replacement_id = :current_user_id and
			a.start_date::date <= now()::date and
			a.end_date::date >= now()::date
        "
	db_foreach absence_replacement $sql {
	    if {"" ne $owner_id} { lappend replacement_ids $owner_id}
	}
    }

    # Check if the current user is replacing users during their vacations
    # Fraber 2024-04-05: vacation_replacement_id on persons not im_employees, adding 2nd version below
    if {[im_column_exists im_employees vacation_replacement_id]} {
	set sql "
		select	e.employee_id
		from	im_employees e
		where	e.vacation_replacement_id = :current_user_id
        "
	db_foreach employee_vacation_replacement $sql {
	    if {"" ne $employee_id} { lappend replacement_ids $employee_id}
	}
    }

    if {[im_column_exists persons vacation_replacement_id]} {
	set sql "
		select	pe.person_id
		from	persons pe
		where	pe.vacation_replacement_id = :current_user_id
        "
	db_foreach person_vacation_replacement $sql {
	    if {"" ne $person_id} { lappend replacement_ids $person_id}
	}
    }

    return $replacement_ids
}


ad_proc -public im_workflow_task_action {
    -task_id:required
    -action:required
    -message:required
} {
    Similar to wf_task_action, but without checking if the current_user_id
    is the holding user. This allows for reassigning tasks even if the task
    was started.
} {
    set user_id [ad_conn user_id]
    set peer_ip [ad_conn peeraddr]
    set case_id [db_string case "select case_id from wf_tasks where task_id = :task_id" -default 0]
    set action_pretty [lang::message::lookup "" intranet-workflow.Action_$action $action]

    set journal_id [im_workflow_new_journal \
	-case_id $case_id \
	-action $action \
	-action_pretty $action_pretty \
	-message $message \
    ]

    db_string cancel_action "select workflow_case__end_task_action (:journal_id, :action, :task_id)"

    return $journal_id
}



# ----------------------------------------------------------------------
# Inbox for "Business Objects"
# ----------------------------------------------------------------------

ad_proc -public im_workflow_home_inbox_component {
    {-view_name "workflow_home_inbox" }
    {-order_by_clause ""}
    {-relationship "assignment_group" }
    {-relationships {holding_user assignment_group none} }
    {-filter_workflow_key ""}
    {-filter_object_type ""}
    {-filter_subtype_id ""}
    {-filter_status_id ""}
    {-filter_owner_id ""}
    {-filter_assignee_id ""}
    {-filter_wf_action "" }
} {
    Returns a HTML table with the list of workflow tasks for the
    current user.
    Assumes that all shown objects are ]po[ "Business Objects", so 
    we can show sub-type and status of the objects.
    @param show_relationships Determines which relationships to show.
	   Showing more general relationship implies showing more
	   specific ones:<ul>
	   <li>holding_user:	The current iser has started the WF task. 
				Nobody else can execute the task, unless an 
				admin "steals" the task.
	   <li>my_object:	The current user initially created the 
				underlying object. So he can follow-up on
				the status of his expenses, vacations etc.
	   <li>specific_assignment: User has specifically been assigned
				to be the one to execute the task
	   <li>assignment_group:User belongs to the group of users 
				assigned to the task.
	   <li>vacation_group:	User belongs to the vacation replacements
	   <li>object_owner:	Users owns the underyling biz object.
	   <li>object_write:	User has the right to modify the
				underlying business object.
	   <li>object_read:	User has the right to read the 
				underlying business object.
	   <li>none:		The user has no relationship at all
				with the task to complete.
    @paramm relationship Determines a single relationship 
} {
    set bgcolor(0) " class=roweven "
    set bgcolor(1) " class=rowodd "

    set sql_date_format "YYYY-MM-DD"
    set current_user_id [ad_conn user_id]
    set return_url [im_url_with_query]
    set view_id [db_string get_view_id "select view_id from im_views where view_name=:view_name"]
    set user_is_admin_p [im_is_user_site_wide_or_intranet_admin $current_user_id]

    set form_vars [ns_conn form]
    if {"" == $form_vars} { set form_vars [ns_set create] }

    # Vacation Absence Logic: Who does the current user replace?
    set replacement_ids [im_workflow_replacing_vacation_users]

    # Order_by logic: Get form HTTP session or use default
    if {"" == $order_by_clause} {
	set order_by [im_opt_val -limit_to nohtml "wf_inbox_order_by"]
	set order_by_clause [db_string order_by "
		select	order_by_clause
		from	im_view_columns
		where	view_id = :view_id and
			column_name = :order_by
	" -default ""]
    }

    # Calculate the current_url without "wf_inbox_order_by" variable
    set current_url "[ns_conn url]?"
    ns_set delkey $form_vars wf_inbox_order_by
    set form_vars_size [ns_set size $form_vars]
    for { set i 0 } { $i < $form_vars_size } { incr i } {
	set key [ns_set key $form_vars $i]
	if {"" == $key} { continue }

	# Security check for cross site scripting
        if {![regexp {^[a-zA-Z0-9_\-]*$} $key]} {
            im_security_alert \
		-location im_workflow_home_inbox_component \
                -message "Invalid URL var characters" \
                -value [ns_quotehtml $key]
            # Quote the harmful keys
            regsub -all {[^a-zA-Z0-9_\-]} $key "_" key
        }

	set value [im_opt_val -limit_to nohtml $key]
	append current_url "$key=[ns_urlencode $value]"
	ns_log Notice "im_workflow_home_inbox_component: i=$i, key=$key, value=$value"
	if { $i < [expr {$form_vars_size-1}] } { append url_vars "&" }
    }

    if {"" == $order_by_clause} {
	set order_by_clause [parameter::get_from_package_key -package_key "intranet-workflow" -parameter "HomeInboxOrderByClause" -default "creation_date"]
    }

    # Let Admins see everything
    if {[im_is_user_site_wide_or_intranet_admin $current_user_id]} { set relationship "none" }

    # Set relationships based on a single variable
    case $relationship {
	holding_user { set relationships {my_object holding_user}}
	my_object { set relationships {my_object holding_user}}
	specific_assignment { set relationships {my_object holding_user specific_assigment}}
	assignment_group { set relationships {my_object holding_user specific_assigment assignment_group}}
	object_owner { set relationships {my_object holding_user specific_assigment assignment_group object_owner}}
	object_write { set relationships {my_object holding_user specific_assigment assignment_group object_owner object_write}}
	object_read { set relationships {my_object holding_user specific_assigment assignment_group object_owner object_write object_read}}
	none { set relationships {my_object holding_user specific_assigment assignment_group object_owner object_write object_read none}}
    }

    # ---------------------------------------------------------------
    # Columns to show
  
    set column_sql "
	select	column_id,
		column_name,
		column_render_tcl,
		visible_for,
		extra_select,
		extra_from,
		extra_where,
		(order_by_clause is not null) as order_by_clause_exists_p
	from	im_view_columns
	where	view_id = :view_id
	order by sort_order, column_id
    "
    set column_vars [list]

    set extra_selects [list]
    set extra_froms [list]
    set extra_wheres [list]

    set colspan 1
    set table_header_html "<tr class=\"list-header\">\n"
    db_foreach column_list_sql $column_sql {
	if {"" == $visible_for || [eval $visible_for]} {
	    lappend column_vars "$column_render_tcl"

	    if {"" ne $extra_select} { lappend extra_selects [eval "set a \"$extra_select\""] }
	    if {"" ne $extra_from} { lappend extra_froms $extra_from }
	    if {"" ne $extra_where} { lappend extra_wheres $extra_where }
	    if {"" ne $order_by_clause && $order_by == $column_name} { set view_order_by_clause $order_by_clause }

	    # Only localize reasonable columns
	    if {[regexp {^[a-zA-Z0-9_]+$} $column_name]} {
		regsub -all " " $column_name "_" col_key
		set column_name [lang::message::lookup "" intranet-workflow.$col_key $column_name]
	    }

	    set col_url [export_vars -base $current_url {{wf_inbox_order_by $column_name}}]
	    set admin_link "<a href=[export_vars -base "/intranet/admin/views/new-column" {return_url column_id {form_mode edit}}] target=\"_blank\">[im_gif wrench]</a>"
	    if {!$user_is_admin_p} { set admin_link "" }
	    if {"f" == $order_by_clause_exists_p} {
		append table_header_html "<th class=\"list\">$column_name$admin_link</td>\n"
	    } else {
		append table_header_html "<th class=\"list\"><a href=\"$col_url\">$column_name</a>$admin_link</td>\n"
	    }
	    incr colspan
	}
    }

    append table_header_html "</tr>\n"


    # ---------------------------------------------------------------
    # SQL Query

    set where_clause [join $extra_wheres " and\n            "]
    if { $where_clause ne "" } { set where_clause " and $where_clause" }
    
    set extra_select [join $extra_selects ",\n\t"]
    if { $extra_select ne "" } { set extra_select ",\n\t$extra_select" }
    
    set extra_from [join $extra_froms ",\n\t"]
    if { $extra_from ne "" } { set extra_from ",\n\t$extra_from" }
    
    set extra_where [join $extra_wheres "and\n\t"]
    if { $extra_where ne "" } { set extra_where ",\n\t$extra_where" }

    # The list of all "deleted" states of all ]po[ object type
    # This list needs to grow when adding new object types.
    #  49 		# Intranet Company Status 
    #  82 		# Intranet Project Status
    #  3503 		# Intranet Investment Status
    #  3812 		# Intranet Cost Status
    #  10100 		# Intranet Employee Pipeline State
    #  10131 		# Intranet Invoice Status
    #  11002 		# Intranet SQL Selector Status
    #  11402 		# Intranet Notes Status
    #  15002 		# Intranet Report Status
    #  16002 		# Intranet Absence Status
    #  17090 		# Intranet Timesheet Conf Status
    #  30097 		# Intranet Ticket Status
    #  47001 		# Intranet Invoice Item Status
    #  71002 		# Intranet Baseline Status
    #  73002 		# Intranet Planning Status
    #  75098 		# Intranet Risk Status
    #  85002 		# Intranet Rule Status
    #  86002 		# Intranet Sencha Preferences Status
    #  86202 		# Intranet Sencha Column Configurations Status
    set deleted_status_ids {49 82 3503 3812 10100 10131 11002 11402 15002 16002 17090 30097 47001 71002 73002 75098 85002 86002 86202}

    # Get the list of all "open" (=enabled or started) tasks with their assigned users
    set tasks_sql "
	select  t.*
	from    (
		select
			ot.pretty_name as object_type_pretty,
			o.object_id,
			o.creation_user as owner_id,
			o.creation_date,
			im_name_from_user_id(o.creation_user) as owner_name,
			acs_object__name(o.object_id) as object_name,
			im_biz_object__get_type_id(o.object_id) as type_id,
			im_biz_object__get_status_id(o.object_id) as status_id,
			ca.workflow_key,
			wft.pretty_name as workflow_name,
			tr.transition_name,
			tr.transition_key,
			t.holding_user,
			t.task_id,
			im_workflow_task_assignee_names(t.task_id) as assignees_pretty
			$extra_select
		from
			acs_object_types ot,
			acs_objects o,
			wf_cases ca,
			wf_transitions tr,
			wf_tasks t,
			acs_object_types wft
			$extra_from
		where
			ot.object_type = o.object_type
			and o.object_id = ca.object_id
			and ca.case_id = t.case_id
			and ca.state in ('created', 'active')
			and t.state in ('enabled', 'started')
			and t.transition_key = tr.transition_key
			and t.workflow_key = tr.workflow_key
			and ca.workflow_key = wft.object_type
			and (:filter_workflow_key is null OR ca.workflow_key = :filter_workflow_key)
			and (:filter_object_type is null OR o.object_type = :filter_object_type)
			and (:filter_owner_id is null OR o.creation_user = :filter_owner_id)
			and (:filter_assignee_id is null OR (
				t.task_id in (select task_id from wf_task_assignments where party_id = :filter_assignee_id)
			))
			$extra_where
	       ) t
	where
		t.status_id not in ([join $deleted_status_ids ","]) and
		(:filter_status_id is null OR :filter_status_id = t.status_id)
    "

    # ad_return_complaint 1 "<pre>$tasks_sql</pre><br>[im_ad_hoc_query -format html $tasks_sql]"

    if {"" != $order_by_clause} {
	append tasks_sql "\torder by $order_by_clause"
    }

    # ---------------------------------------------------------------
    # Store the conf_object_id -> assigned_user relationship in a Hash array
    set tasks_assignment_sql "
    	select
		t.*,
		m.member_id as assigned_user_id
	from
		($tasks_sql) t
		LEFT OUTER JOIN (
			select distinct
				m.member_id,
				ta.task_id
			from	wf_task_assignments ta,
				party_approved_member_map m
			where	m.party_id = ta.party_id
		) m ON t.task_id = m.task_id
    "
    db_foreach assigs $tasks_assignment_sql {
	set assigs ""
    	if {[info exists assignment_hash($object_id)]} { set assigs $assignment_hash($object_id) }
	lappend assigs $assigned_user_id
	set assignment_hash($object_id) $assigs
    }

    # ---------------------------------------------------------------
    # Format the Result Data

    set ctr 0
    set table_body_html ""
    db_foreach tasks $tasks_sql {

        # Only show entries matching the wf_action
        set wf_action "$workflow_key.$transition_key"
        if {"" ne $filter_wf_action && $filter_wf_action ne $wf_action} { continue }

	set assigned_users ""
	set assignees_pretty [im_workflow_replace_translations_in_string $assignees_pretty]
	set assignee_pretty $assignees_pretty

    	if {[info exists assignment_hash($object_id)]} { set assigned_users $assignment_hash($object_id) }

	# Determine the type of relationship to the object - why is the task listed here?
	# The problem: There may be more then one relationship, so we need to pull out the
	# most relevant one. Maybe reorganize the code later to enable all rels as a bitmap
	# and the all of the rels in the inbox...
	set rel "none"
	if {[lsearch $replacement_ids $owner_id] > -1} { set rel "my_object" }
	foreach assigned_user_id $assigned_users {
	    if {[lsearch $replacement_ids $assigned_user_id] > -1 && $rel ne "holding_user"} { 
		set rel "assignment_group" 
	    }
	    if {[lsearch $replacement_ids $holding_user] > -1} { 
		set rel "holding_user" 
	    }
	}

	# Skip if not related to the user
	if {[lsearch $relationships $rel] == -1} { continue }

	# L10ned version of next action
	regsub -all " " $transition_name "_" next_action_key
	set next_action_l10n [lang::message::lookup "" intranet-workflow.$next_action_key $transition_name]
	set object_subtype [im_category_from_id $type_id]
	set status [im_category_from_id $status_id]
	set object_url "[im_biz_object_url $object_id "view"]&return_url=[ns_urlencode $return_url]"
	set owner_url [export_vars -base "/intranet/users/view" {return_url {user_id $owner_id}}]
	
	set action_hash($transition_key) $next_action_l10n
	set action_url [export_vars -base "/[im_workflow_url]/task" {return_url task_id}]
	set action_link "<a href=$action_url>$next_action_l10n</a>"

	# Don't show the "Action" link if the object is mine...
	if {"my_object" == $rel} {
	    set action_link $next_action_l10n
	} 

	# L10ned version of the relationship of the user to the object
	set relationship_l10n [lang::message::lookup "" intranet-workflow.$rel $rel]

	set row_html "<tr$bgcolor([expr {$ctr % 2}])>\n"
	foreach column_var $column_vars {
	    append row_html "\t<td valign=top>"
	    set cmd "append row_html $column_var"
	    eval "$cmd"
	    append row_html "</td>\n"
	}
	append row_html "</tr>\n"
	append table_body_html $row_html
	incr ctr
    }

    # Show a reasonable message when there are no result rows:
    if { $table_body_html eq "" } {
	set table_body_html "
	<tr><td colspan=$colspan><ul><li><b> 
	[lang::message::lookup "" intranet-core.lt_There_are_currently_n "There are currently no entries matching the selected criteria"]
	</b></ul></td></tr>"
    }

    # ---------------------------------------------------------------
    # Return results
    
    set admin_action_options ""
    if {$user_is_admin_p} {

	append admin_action_options "<option value=\"terminate_wf\">[lang::message::lookup "" intranet-workflow.Terminate_Workflow "Terminate Workflow"]</option>\n"
	append admin_action_options "<option value=\"nuke\">[lang::message::lookup "" intranet-workflow.Nuke_Object "Nuke Object (Admin only)"]</option>\n"
    }

    foreach wf_trans [lsort [array names action_hash]] {
	set wf_trans_l10n $action_hash($wf_trans)
	append admin_action_options "<option value=\"$wf_trans\">$wf_trans_l10n</option>\n"
    }

    set table_action_html "
	<tr class=rowplain>
	<td colspan=99 class=rowplain align=left>
	    <select name=\"operation\">
	    <option value=\"delete_membership\">[lang::message::lookup "" intranet-workflow.Remove_From_Inbox "Remove from Inbox"]</option>
	    $admin_action_options
	    </select>
	    <input type=submit name=submit value='[lang::message::lookup "" intranet-workflow.Submit "Submit"]'>
	</td>
	</tr>
    "
    set enable_bulk_action_p [parameter::get_from_package_key -package_key "intranet-workflow" -parameter "EnableWorkflowInboxBulkActionsP" -default 0]
    set wf_bulk_action_priv_p [db_string wf_bulk_action_priv "select count(*) from acs_privileges where privilege = 'wf_bulk_action'"]
    if {$wf_bulk_action_priv_p} {
	set enable_bulk_action_p [im_permission $current_user_id "wf_bulk_action"]
    }
    if {!$enable_bulk_action_p} { set table_action_html "" }


    # ---------------------------------------------------------------
    # Filters
    # ---------------------------------------------------------------

    # Options for the type of the workflow
    set active_cases_l10n [lang::message::lookup "" intranet-workflow.active_cases "active cases"]
    set wf_options_sql "
	select	distinct
		pretty_name || ' (' || active_cases || ' ' || '$active_cases_l10n' || ')',
		object_type
	from	(select	ot.pretty_name,
			ot.object_type,
			(select count(*) from wf_cases wfc where ot.object_type = wfc.workflow_key and state in ('active')) as active_cases
		from	acs_object_types ot
		) t
	where
		active_cases > 0
	order by
		pretty_name || ' (' || active_cases || ' ' || '$active_cases_l10n' || ')'
    "
    # ad_return_complaint 1 $wf_options_sql

    set workflow_options [db_list_of_lists wf $wf_options_sql]
    set workflow_options [linsert $workflow_options 0 [list [_ intranet-core.All] ""]]
    set workflow_select [im_select -translate_p 0 -ad_form_option_list_style_p 1 filter_workflow_key $workflow_options $filter_workflow_key]

    # Options for the type of object
    set object_type_sql {
	select distinct
    		ot.pretty_name,
	        ot.object_type
	from	acs_object_types ot,
                acs_objects o,
                wf_cases wc
	where	o.object_type = ot.object_type and
                o.object_id = wc.object_id
	order by
		ot.pretty_name
    }
    set object_type_options [db_list_of_lists otypes $object_type_sql]
    set object_type_options [linsert $object_type_options 0 [list [_ intranet-core.All] ""]]
    set object_type_select [im_select -translate_p 0 -ad_form_option_list_style_p 1 filter_object_type $object_type_options $filter_object_type]


    # Options for the task type
    set wf_action_sql "
        select distinct
                workflow_name || ' - ' || transition_name as value,
                workflow_key || '.' || t.transition_key as key
        from    ($tasks_sql) t
        order by workflow_key || '.' || t.transition_key, workflow_name || ' - ' || transition_name
    "
    # ad_return_complaint 1 [im_ad_hoc_query -format html $wf_action_sql]
    set wf_action_options [db_list_of_lists wfa $wf_action_sql]
    set wf_action_options [linsert $wf_action_options 0 [list [_ intranet-core.All] ""]]
    set wf_action_select [im_select -translate_p 0 -ad_form_option_list_style_p 1 filter_wf_action $wf_action_options $filter_wf_action]


    # Options for owner
    set owner_sql {
	select distinct
    		im_name_from_user_id(o.creation_user),
		o.creation_user
	from	wf_cases wfc,
                acs_objects o
	where	o.object_id = wfc.case_id and
		wfc.state in ('active')
	order by
		im_name_from_user_id(o.creation_user)
    }
    set owner_options [db_list_of_lists otypes $owner_sql]
    set owner_options [linsert $owner_options 0 [list [_ intranet-core.All] ""]]
    set owner_select [im_select -translate_p 0 -ad_form_option_list_style_p 1 filter_owner_id $owner_options $filter_owner_id]


    # Options for assignee
    set assignee_sql {
	select distinct
    		im_name_from_user_id(assignee_id),
		assignee_id
	from	(
			select	wfta.party_id as assignee_id
			from	wf_cases wfc,
				wf_tasks wft,
				wf_task_assignments wfta
			where	wfc.state in ('active') and
				wfc.case_id = wft.case_id and
				wft.state in ('started', 'enabled') and
				wft.task_id = wfta.task_id
		) t
	order by
		im_name_from_user_id(assignee_id)
    }
    set assignee_options [db_list_of_lists otypes $assignee_sql]
    set assignee_options [linsert $assignee_options 0 [list [_ intranet-core.All] ""]]
    set assignee_select [im_select -translate_p 0 -ad_form_option_list_style_p 1 filter_assignee_id $assignee_options $filter_assignee_id]


    # Format the filters
    set return_url [im_url_with_query]
    set filter_passthrough_vars [list]
    set form_vars [ns_conn form]
    if {"" == $form_vars} { set form_vars [ns_set create] }
    array set form_hash [ns_set array $form_vars]
    foreach var [array names form_hash] {
        if {$var in {"filter_object_type" "filter_workflow_key" "filter_wf_action" "filter_owner_id" "filter_assignee_id"}} { continue }
	set val [im_opt_val -limit_to nohtml $var]
        lappend filter_passthrough_vars [list $var $val]
    }

    return "
	<script type=\"text/javascript\" nonce=\"[im_csp_nonce]\">
	window.addEventListener('load', function() {
	    document.getElementById('list_check_all_workflow').addEventListener('click', function() { acs_ListCheckAll('action', this.checked) });
	});
	</script>

        <form action=[ad_conn url] method=GET>
        [export_vars -form $filter_passthrough_vars]
<table cellspacing=0 cellpadding=0 border=0>
<tr>
<td>
<!-- <b>[_ intranet-core.Filter]</b>: &nbsp; -->
<nobr>[_ acs-workflow.Object_Type]: $object_type_select</nobr> &nbsp; 
<nobr>[_ intranet-workflow.Workflow]: $workflow_select</nobr> &nbsp; 
<nobr>[lang::message::lookup "" intranet-workflow.Owner "Owner"]: $owner_select</nobr> &nbsp; 
<nobr>[lang::message::lookup "" intranet-workflow.Assignee "Assignee"]: $assignee_select</nobr> &nbsp; 
<nobr>[_ intranet-helpdesk.Action]: $wf_action_select</nobr> &nbsp; 
<input type=submit value=[_ intranet-core.Filter]>
</td>
</tr>
</table>
        </form>

	<form action=\"/intranet-workflow/inbox-action\" method=POST>
	[export_vars -form {return_url}]
	<table class=\"table_list_page\">
	  $table_header_html
	  $table_body_html
	  $table_action_html
	</table>
	</form>
    "
}


# ---------------------------------------------------------------
# Skip the first tasks of the workflow.
# This is useful for the very first transition of an approval WF

ad_proc -public im_workflow_skip_first_transition {
    -case_id:required
} {
    Skip the first tasks of the workflow.
    This is useful for the very first transition of an approval WF
    There can be potentially more than one of such tasks..
} {
    set user_id [ad_conn user_id]

    # Assign the first task to the user himself and start the task
    # Fraber 151102: Assign to anonymous user in order to suppress email alerts
    set wf_modify_assignee $user_id

    # Get the first "enabled" task of the new case_id:
    # These enabled tasks should have their normal assignments already
    set enabled_tasks [db_list enabled_tasks "
		select	task_id
		from	wf_tasks
		where	case_id = :case_id and
			transition_key = 'modify' and
			state = 'enabled'
    "]
    ns_log Notice "im_workflow_skip_first_transition: user_id=$user_id, enabled_tasks=$enabled_tasks"

    foreach task_id $enabled_tasks {
	ns_log Notice "im_workflow_skip_first_transition: task_id=$task_id"

	# We are doing a manual assignment for user_id because we are going to 'process' it
	# We do the assignment using a manual insert to avoid notifying the user.
	set assig_exists_p [db_string assig_exists_p "select count(*) from wf_task_assignments where task_id = :task_id and party_id = :user_id"]
	if {!$assig_exists_p} {
	    db_dml assig "insert into wf_task_assignments (task_id, party_id) values (:task_id, :user_id)"
	}

	# Start the task. Saves the user the work to press the "Start Task" button.
	ns_log Notice "im_workflow_skip_first_transition: select workflow_case__begin_task_action ($task_id, 'start', '[ad_conn peeraddr]', $user_id, '')"
	set journal_id [db_string wf_action "select workflow_case__begin_task_action (:task_id, 'start', '[ad_conn peeraddr]', :user_id, '')"]
	ns_log Notice "im_workflow_skip_first_transition: select workflow_case__start_task ($task_id, $user_id, $journal_id)"
	set journal_id2 [db_string wf_start "select workflow_case__start_task (:task_id, :user_id, :journal_id)"]

	# Finish the task. That forwards the token to the next transition.
	ns_log Notice "im_workflow_skip_first_transition: select workflow_case__finish_task($task_id, $journal_id)"
	set journal_id3 [db_string wf_finish "select workflow_case__finish_task(:task_id, :journal_id)"]
    }
}



# ----------------------------------------------------------------------
# Workflow Permissions
#
# Check permissions represented as a list of letters {r w d a}
# per business object based on role, object type and object status.
#
# There is a default logic:
# 	1. (role, status, type) is checked.
# 	2. (role, type) is checked.
#	3. (role, status) is checked.
#	4. (role) is checked.
#
# 2.) and 3.) are OK, because type and status are disjoint.
# ----------------------------------------------------------------------

ad_proc im_workflow_object_permissions {
    -object_id:required
    -perm_table:required
} {
    Determines whether a user can execute the specified
    "perm_letter" (i.e. r=read, w=write, d=delete) operation
    on the object.
    Returns the list of permissions.
} {
    # stuff permission from table into hash
    array set perm_hash $perm_table

    # ------------------------------------------------------
    # Pull out the relevant variables
    set user_id [ad_conn user_id]
    set owner_id [db_string owner "select creation_user from acs_objects where object_id = $object_id" -default 0]
    if {"" == $owner_id} { set owner_id 0 }
    set status_id [db_string status "select im_biz_object__get_status_id (:object_id)" -default 0]
    set type_id [db_string status "select im_biz_object__get_type_id (:object_id)" -default 0]
    set user_is_admin_p [im_is_user_site_wide_or_intranet_admin $user_id]
    set user_is_hr_p [im_user_is_hr_p $user_id]
    set user_is_accounting_p [im_user_is_accounting_p $user_id]
    set user_is_owner_p [expr {$owner_id == $user_id}]
    set user_is_assignee_p [db_string assignee_p "
	select	count(*)
	from	(select	pamm.member_id
		from	wf_cases wfc,
			wf_tasks wft,
			wf_task_assignments wfta,
			party_approved_member_map pamm
		where	wfc.object_id = :object_id
			and wft.case_id = wfc.case_id
			and wft.state in ('enabled', 'started')
			and wft.task_id = wfta.task_id
			and wfta.party_id = pamm.party_id
			and pamm.party_id = :user_id
		) t
    "]
    
    ns_log Notice "im_workflow_object_permissions: status_id=$status_id, user_id=$user_id, owner_id=$owner_id"
    ns_log Notice "im_workflow_object_permissions: user_is_owner_p=$user_is_owner_p, user_is_assignee_p=$user_is_assignee_p, user_is_hr_p=$user_is_hr_p, user_is_admin_p=$user_is_admin_p"
    ns_log Notice "im_workflow_object_permissions: hash=[array get perm_hash]"

    if {0 == $status_id} {
	ad_return_complaint 1 "<b>Invalid Configuration</b>:<br>The PL/SQL function 'im_biz_object__get_status_id (:object_id)' has returned an invalid status_id for object #$object_id.  "
    }

    # ------------------------------------------------------
    # Calculate permissions
    set perm_set {}

    if {$user_is_owner_p} { 
	set perm_letters {}
	if {[info exists perm_hash(owner-$status_id)]} { set perm_letters $perm_hash(owner-$status_id)}
	set perm_set [set_union $perm_set $perm_letters]
    }
 
    if {$user_is_assignee_p} { 
	set perm_letters {}
	if {[info exists perm_hash(assignee-$status_id)]} { set perm_letters $perm_hash(assignee-$status_id)}
	set perm_set [set_union $perm_set $perm_letters]
    }

    if {$user_is_hr_p} { 
	set perm_letters {}
	if {[info exists perm_hash(hr-$status_id)]} { set perm_letters $perm_hash(hr-$status_id)}
	set perm_set [set_union $perm_set $perm_letters]
    }

    if {$user_is_accounting_p} { 
	set perm_letters {}
	if {[info exists perm_hash(accounting-$status_id)]} { set perm_letters $perm_hash(accounting-$status_id)}
	set perm_set [set_union $perm_set $perm_letters]
    }

    # Admins can do everything anytime.
    if {$user_is_admin_p} { set perm_p {v r w d a } }

    return $perm_set
}





# ---------------------------------------------------------------
# Cancel the workflow in case the underlying object gets closed, 
# such like a ticket of a deleted project.
#

ad_proc im_workflow_cancel_workflow {
    {-object_id ""}
    {-case_id ""}
} {
    Cancel the workflow in case the underlying object gets closed, 
    such like a ticket of a deleted project.
} {
    set journal_id ""

    set case_ids [list $case_id]
    if {"" ne $object_id} {
	set case_ids [db_list case_ids "select case_id from wf_cases where object_id = :object_id"]
    }
    lappend case_ids 0

    # Delete all tokens of the case
    db_dml delete_tokens "
    	delete from wf_tokens
    	where case_id in ([join $case_ids ","]) and
    	state in ('free', 'locked')
    "
    
    set cancel_tasks_sql "
    	select 	task_id as wf_task_id
    	from	wf_tasks
    	where	case_id in ([join $case_ids ","]) and
		state in ('started')
    "
    db_foreach cancel_started_tasks $cancel_tasks_sql {
        ns_log Notice "im_workflow_cancel_workflow: canceling task $wf_task_id"
        set journal_id [im_workflow_task_action -task_id $wf_task_id -action "cancel" -message "Canceling workflow"]
    }

    # fraber 101112: 
    # ToDo: Validate that it's OK just to change the status of a task to "canceled"
    # in order to disable it. Or should the task be deleted?
    #
    set del_enabled_tasks_sql "
    	select 	task_id as wf_task_id
    	from	wf_tasks
    	where	case_id in ([join $case_ids ","]) and
		state in ('enabled')
    "
    db_foreach cancel_started_tasks $del_enabled_tasks_sql {
        ns_log Notice "im_workflow_cancel_workflow: deleting enabled task $wf_task_id"
	db_dml del_task "update wf_tasks set state = 'canceled' where task_id = :wf_task_id"
    }

    # Cancel the case itself
    db_dml cancel_case "update wf_cases set state = 'canceled' where case_id in ([join $case_ids ","])"

}

