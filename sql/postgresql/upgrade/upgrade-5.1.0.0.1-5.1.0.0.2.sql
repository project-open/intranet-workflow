-- 5.1.0.0.1-5.1.0.0.2.sql
SELECT acs_log__debug('/packages/intranet-workflow/sql/postgresql/upgrade/upgrade-5.1.0.0.1-5.1.0.0.2.sql','');

\ir ../workflow-bankholiday_approval_wf-drop.sql
\ir ../workflow-bankholiday_approval_wf-create.sql

-- Install bankholiday_approval_wf for absences of type Bank Holiday
update im_categories set aux_string1 = 'bankholiday_approval_wf' where category_id = 5005;

