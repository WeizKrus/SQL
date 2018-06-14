select top 10 MACTIONS, * from NT_LOG
where CTBL_NAME = 'EMPLOYEE'
order by ILOG_KEY desc


select SUPID, * from EMPLOYEE
where CEMPID = '      6        '