select 
	pro.name_profile 
	,rep.name_report
from k_profiles_modules_rights pmr
join k_profiles pro
	on pro.id_profile = pmr.id_profile
join k_modules_rights mr
	on mr.id_module_right = pmr.id_module_right
join k_modules md
	on md.id_module = mr.id_module
join k_rights rig
	on rig.id_right = mr.id_right
join k_modules_types mt
	on mt.id_module_type = md.id_module_type
join k_reports rep
	on rep.id_report = md.id_item
where mt.name_module_type = 'report'
	and rig.name_right = 'EXC_read'
	and pro.name_profile <> 'GV_Administrator'
order by
	pro.name_profile
	,rep.name_report
