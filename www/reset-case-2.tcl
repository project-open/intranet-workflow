# /packages/intranet-workflow/www/projects/rfc-delete-2.tcl
#

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
    { action_pretty "" }
}

# ---------------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------------

set user_id [auth::require_login]
set peer_ip [ad_conn peeraddr]
set page_title [lang::message::lookup "" intranet-workflow.Reset_Workflow_Case "Reset Workflow Case"]
set date_format "YYYY-MM-DD"

set bgcolor(0) " class=roweven"
set bgcolor(1) " class=rowodd"

# ---------------------------------------------------------------------
# Cancel all transitions and move to "rfc_cancel"
# ---------------------------------------------------------------------


if {"" != $button_confirm} {
    
    # Get the general case_id
    # "Cancel" all the task in the current case
    if {0 == $case_id} {
	set case_id [db_string case "select case_id from wf_tasks where task_id = :task_id" -default 0]
    }

    if {0 == $case_id} {
	ad_return_complaint 1 "Didn't find case_id"
	ad_script_abort
    }

    # Get the places of tokens before canceling the case
    set places [db_list token_in_places "select	place_key||':'||state from wf_tokens where case_id = :case_id and state in ('free', 'locked')"]
    set reset_message "Resetting workflow case #$case_id with tokens in [join $places ", "]"
    # if {[llength $places] == 0} { set message "Resetting Workflow with no tokens active" }
    # set case_journal_id [im_workflow_new_journal -case_id $case_id -action "reset_workflow" -action_pretty "Reset Workflow" -message $message]

    # Make sure the case is active
    db_dml update_case "update wf_cases set state = 'active' where case_id = :case_id"

    # Delete active tokens, leave old ones in their places
    db_dml delete_tokens "delete from wf_tokens where case_id = :case_id and state in ('free', 'locked')"
    
    set tasks_sql "
    	select task_id as wf_task_id
    	from wf_tasks
    	where case_id = :case_id
    	      and state in ('started')
    "
    db_foreach tasks $tasks_sql {
        ns_log Notice "new-rfc: canceling task $wf_task_id"

	set message "Canceling task #$task_id in case #$case_id as part of WF reset"
	set journal_id [im_workflow_new_journal -case_id $case_id -action "cancel" -action_pretty "Cancel Task" -message $message]
	db_string cancel_task "select workflow_case__cancel_task(:wf_task_id, :journal_id)"
        # set journal_id [im_workflow_task_action -task_id $wf_task_id -action "cancel" -message "Cancel task"]
    }

    db_string start "select workflow_case__start_case(:case_id, :user_id, :peer_ip, :reset_message)"

    # Re-activate the case. Not sure why the case can get "finished" during wf__start_case, but it seems to happen...
    # db_dml update_case "update wf_cases set state = 'active' where case_id = :case_id"


    # Skip the very first transition as always
    # im_workflow_skip_first_transition -case_id $case_id

    # Continue to "move
    # set sweep_journal_id [im_workflow_new_journal -case_id $case_id -action "sweep" -action_pretty "Sweeping workflow" -message "Sweeping workflow"]
    # im_exec_dml sweep "workflow_case__sweep_automatic_transitions (:case_id, :sweep_journal_id)"
}

