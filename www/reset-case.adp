<master>
<property name="doc(title)">@page_title;literal@</property>
<property name="main_navbar_label">rfc</property>

<h1><%= [lang::message::lookup "" intranet-workflow.Confirm_reset_action "Confirm %action_pretty%"] %></h1>

<%= [lang::message::lookup "" intranet-workflow.Do_you_really_want_to_action "Do you really want to perform action '%action_pretty%'?"] %>
<p>&nbsp;</p>

<form action=reset-case-2 method=POST>
<%= [export_vars -form {return_url case_id task_id place_key action action_pretty}] %>
<input type="submit" name="button_cancel" value="<%= [lang::message::lookup "" intranet-workflow.Cancel_Button "Cancel"] %>">
<input type="submit" name="button_confirm" value="<%= [lang::message::lookup "" intranet-workflow.Confirm_Button "Confirm %action_pretty%"] %>">
</form>
