# /packages/intranet-workflow/www/reset-case-2.tcl

ad_page_contract {
    View all the info about a specific project.

    @param orderby the display order
    @param show_all_comments whether to show all comments

    @author mbryzek@arsdigita.com
    @author Frank Bergmann (frank.bergmann@project-open.com)
} {
    { button_cancel "" }
    { button_confirm "" }
    { task_id:integer 0 }
    { case_id:integer 0 }
    return_url
    { place_key "tagged" }
    { action "undefined" }
    { action_pretty "Undefined" }
}

# ---------------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------------

set current_user_id [auth::require_login]
set peer_ip [ad_conn peeraddr]
set page_title [lang::message::lookup "" intranet-workflow.Reset_Workflow_Case "Reset Workflow Case"]
set date_format "YYYY-MM-DD"

set bgcolor(0) " class=roweven"
set bgcolor(1) " class=rowodd"

set user_is_admin_p [im_is_user_site_wide_or_intranet_admin $current_user_id]
if {!$user_is_admin_p} {
    ad_return_complaint 1 "You are not an admin"
    ad_script_abort
}

# ---------------------------------------------------------------------
# Check task_id vs. case_id present
# ---------------------------------------------------------------------


if {"" eq $button_confirm} {
    ad_returnredirect $return_url
    ad_script_abort
}

# Get the general case_id
if {"" ne $task_id && 0 != $task_id && 0 == $case_id} {
    set case_id [db_string case "select case_id from wf_tasks where task_id = :task_id" -default 0]
}

if {0 == $case_id} {
    ad_return_complaint 1 "Didn't find case_id"
    ad_script_abort
}

# Get the workflow_key and the object_id of the existing WF
set workflow_key ""
db_0or1row case_info "select workflow_key, object_id from wf_cases where case_id = :case_id"
if {"" eq $workflow_key} {
    ad_return_complaint 1 "Didn't find workflow_key for case_id=$case_id"
    ad_script_abort
}


# ---------------------------------------------------------------------
# Perform action
# ---------------------------------------------------------------------

switch $action {
    "nuke" {
	ns_log Notice "reset-case-2: Nuking case_id=$case_id"
	# Just delete the case, the rest should go with on delete cascade
	db_dml delete_case "delete from wf_cases where case_id = :case_id"
    }

    "cancel" {
	ns_log Notice "reset-case-2: Canceling  case_id=$case_id"
	im_workflow_new_journal -case_id $case_id -action "cancel WF" -action_pretty "Cancel WF" -message "Canceling WF using 'Cancel Case' action in WF component"
	im_workflow_cancel_workflow -case_id $case_id
    }

    "copy" {
	ns_log Notice "reset-case-2: Copying case_id=$case_id"
	# Start a new workflow case
	set new_case_id [im_workflow_start_wf -object_id $object_id -workflow_key $workflow_key -skip_first_transition_p 1]
    }

    "restart" {
	ns_log Notice "reset-case-2: Restarting case_id=$case_id"

	# Get the places of tokens before canceling the case
	set places [db_list token_in_places "select place_key||':'||state from wf_tokens where case_id = :case_id and state in ('free', 'locked')"]
	set reset_message "Resetting workflow case_id=$case_id with tokens in [join $places ", "]"
	if {[llength $places] == 0} { set reset_message "Resetting Workflow with no tokens active" }
	set reset_journal_id [im_workflow_new_journal -case_id $case_id -action "reset_workflow" -action_pretty "Reset Workflow" -message $reset_message]

	# Cancel any active tasks
	set tasks_sql "
		select	task_id as wf_task_id
		from	wf_tasks
		where	case_id = :case_id and state in ('started')
        "
	db_foreach tasks $tasks_sql {
	    set message "Canceling task_id=$task_id in case_id=$case_id as part of WF reset"
	    set journal_id [im_workflow_new_journal -case_id $case_id -action "cancel" -action_pretty "Cancel Task" -message $message]
	    db_string cancel_task "select workflow_case__cancel_task(:wf_task_id, :journal_id)"
	}

	# All task should have been canceled.
	# The original code for starting a WF is like this:
	# select workflow_case__new (:case_id, :workflow_key, :context_key, :object_id, now(), :user_id, :creation_ip);
        # select workflow_case__start_case (:case_id, :user_id, :creation_ip, null);
	# The case is already there, so we should not execute wf_case__new anymore. It just creates the object.

	# Safe option (working): Delete all tokens and tasks:
	# db_dml delete_tokens "delete from wf_tokens where case_id = :case_id"
	# db_dml delete_tasks "delete from wf_tasks where case_id = :case_id"

	# Softwer option (apparently working): Keep old/finished tasks/tokens in place for audit
	# Delete active tokens, leave old ones in their places
	db_dml delete_tokens "delete from wf_tokens where case_id = :case_id and state in ('free', 'locked')"
	db_dml delete_tasks "delete from wf_tasks where case_id = :case_id and state in ('enabled', 'started')"

	# Start the workflow:
	# Sets wf_case.status = 'active, puts a token in 'start' and sweep_automatic_transitions()
	set start_message "Starting case_id=$case_id again"
	db_string start "select workflow_case__start_case(:case_id, :current_user_id, :peer_ip, :start_message)"

	# Skip the very first transition as always
	im_workflow_skip_first_transition -case_id $case_id
    }

    default {
	ad_return_complaint 1 "Invalid action '$action'"
	ad_script_abort
    }

}

