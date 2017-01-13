<master src="../../intranet-core/www/master">
<property name="doc(title)">@page_title;literal@</property>
<property name="main_navbar_label">workflow</property>
<property name="left_navbar">@left_navbar_html;literal@</property>

<!-- left - right - bottom  design -->

<table cellpadding="0" cellspacing="0" border="0" width="100%">
<tr>
  <td colspan="3">
    <%= [im_component_bay top] %>
  </td>
</tr>
<tr>
  <td valign="top" width="50%">
    <%= [im_component_bay left] %>
  </td>
  <td width=2>&nbsp;</td>
  <td valign="top" width="50%">
    <%= [im_component_bay right] %>
  </td>
</tr>
<tr>
  <td colspan="3">
    @workflow_home_inbox;noquote@
    <%= [im_component_bay bottom] %>
  </td>
</tr>
</table>

