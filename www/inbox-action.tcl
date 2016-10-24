# /intranet-workflow/www/inbox-action.tcl

ad_page_contract {
    Delete a specific task from an inbox
    @author Frank Bergmann <frank.bergmann@project-open.com>
} {
    task_id:multiple,optional
    { operation "" }
    return_url
}


set current_user_id [auth::require_login]
set user_is_admin_p [im_is_user_site_wide_or_intranet_admin $current_user_id]
set subsite_id [ad_conn subsite_id]
set reassign_p [permission::permission_p -party_id $current_user_id -object_id $subsite_id -privilege "wf_reassign_tasks"]

if {![info exists task_id]} { set task_id [list] }


# ad_return_complaint 1 "inbox-action: operation=$operation, task_id=$task_id"

foreach tid $task_id {
    set object_id ""
    set object_type ""
    db_0or1row task_info "
		select	wfc.object_id,
			o.object_type,
			tr.workflow_key,
			tr.transition_key,
			tr.transition_name,
			acs_object__name(wfc.object_id) as object_name
		from	wf_tasks wft,
			wf_cases wfc,
			wf_transitions tr,
			acs_objects o
		where	wft.task_id = :tid and
			wft.case_id = wfc.case_id and
			wfc.object_id = o.object_id and
			wft.workflow_key = tr.workflow_key and
			wft.transition_key = tr.transition_key
    "
    switch $operation {
	delete_membership {

	    # Delete a membership-rel between the user and the object
	    # (if exists, this is the case of a project or a company).
	    im_exec_dml delete_user "user_group_member_del (:object_id, :current_user_id)"
	    
	    # Delete the assignation to all tasks in state "enabled".
	    db_dml del_task_assignments "
		delete from wf_task_assignments
		where	party_id = :current_user_id
			and task_id in (
				select	wft.task_id
				from	wf_tasks wft,
					wf_cases wfc
				where	wfc.object_id = :object_id
					and wft.case_id = wfc.case_id
					and wft.state in ('enabled')
			)
	    "
	}

	nuke {
	    switch $object_type {
		im_ticket - im_project {
		    if {!$user_is_admin_p} { ad_return_complaint 1 "You need to be an administrator to nuke an object." }
		    im_project_nuke $object_id
		}
		default {
		    ad_return_complaint 1 "Unable to nuke objects of type '$object_type'"
		    ad_script_abort
		}
	    }
	}
	default {
            if {$operation ne $transition_key} {
		# Check that the user didn't apply the wrong operation on a task.
		ad_return_complaint 1 "<b>Invalid Operation</b>:<br>&nbsp;<br>
			You are trying to perform bulk action '$operation' <br>
			on a '$transition_key' workflow task. This is not possible.<br>&nbsp;<br>
			Please go back to the previous page and only select <br>
			workflow tasks of type '$transition_key'."
		ad_script_abort
	    }

	    # Check if the current task complies with the following conditions:
	    # - Task is assigned to the current user, or the current user is an admin
	    # - Task doesn't include a custom action panel
	    # - If the task requires a yes/no decision, "yes" is selected
	    #
	    set msg "Batch operation '$operation' from WF inbox"
	    set action "finish"

	    # Get the list of attributes defined in this workflow
	    set attributes [db_list wf_attributes "
		select	attribute_name
		from	acs_attributes
		where	object_type = :workflow_key   
	    "]
	    if {[llength $attributes] > 1} { 
		ad_return_complaint 1 "<b>Unsuitable Workflow</b>:<br>&nbsp;<br>
                      The workflow '$workflow_key' of task '$object_name'<br>
		      is not suitable for workflow bulk actions ('$operation'),<br>
		      because it contains more than one attribute:<br>&nbsp;<br>
		      [join $attributes ", "]<br>&nbsp;<br>
 		      Please perform this workflow task manually."
		      ad_script_abort
	    }
	    set attribute_name [lindex $attributes 0]
	    set attribute_hash($attribute_name) "t"

	    # Check if the current user is assigned to the task and try to self-assign if not.
	    set current_user_assigned_p [db_string task_assigned_users "
		select	count(*)
		from	wf_user_tasks ut
		where	ut.task_id = :tid and
			ut.user_id = :current_user_id
	    "]
	    if {!$current_user_assigned_p} {
		if {!$reassign_p} {
		    ad_return_complaint 1 "<li>[_ intranet-core.lt_You_have_insufficient_1]"
		    return
		} else {
		    wf_case_add_task_assignment -task_id $tid -party_id $current_user_id
		}
	    }

	    set journal_id [wf_task_action \
				-user_id $current_user_id \
				-msg $msg \
				-attributes [array get attribute_hash] \
				-assignments [array get assignments] \
				$tid \
				$action \
	    ]


	}
    }
}

ad_returnredirect $return_url




