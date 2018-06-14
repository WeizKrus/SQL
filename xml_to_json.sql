BEGIN TRAN

-- AG - 5/24/2018 - Convert Legacy Gadget xml to json format for the new dashboard
DECLARE @SEQ INT
DECLARE @MDASHBOARD varchar(max)
DECLARE @CDASHBOARD varchar(max)
DECLARE @TEMP_DT TABLE (SEQ INT, MDASHBOARD varchar(max), CDASHBOARD varchar(max))
DECLARE @DASHBOARD_LOOKUP TABLE(GADGETFILE VARCHAR(100) primary key, GADGETTYPE INT, OLDGADGETSEQ INT, DEFAULT_TITLE varchar(100))
DECLARE @legacy_gadget_config TABLE (gadgetType varchar(100), title varchar(100))
DECLARE @XML XML
DECLARE @TEMP_XML XML
DECLARE @gadgetType varchar(max)
declare @newGadgetType int
declare @ExternalTitle varchar(100)
declare @json_begin varchar(100)
declare @json_end varchar(100)
declare @Id_prop varchar(100)
declare @GadgetType_prop varchar(100)
declare @ExternalTitle_prop varchar(100)
declare @Display_prop varchar(100)
declare @DisplayFalse_prop varchar(100)
declare @json_gadget_string varchar(max)
declare @comma char(1)
declare @config_separator char(2)
DECLARE @CDASHBOARD_VALUES_TBL TABLE (ALL_PARTS varchar(max))
DECLARE @OLDGADGET_SEQ_STR varchar(max)
DECLARE @OLDGADGET_SEQ_TBL TABLE (SEQ int)
DECLARE @OLDGADGET_SEQ int
DECLARE @OLDGADGET_TYPE varchar(100)

set @comma = ','
set @config_separator = '||'

-- json string chunks
set @json_begin = '{"bIconView":false,"DashboardGadgetList":['
set @json_end = '],"cGadgetOrder":""}'
set @Id_prop = '{"cIid":"'
set @GadgetType_prop = '","iGadgetType":"'
set @ExternalTitle_prop = '","cExternalTitle":"'
set @Display_prop = '","isDisplay":true}'
set @DisplayFalse_prop = '","isDisplay":false}'
--set @json_gadget_string = ''

-- Insert the records to lookup table
INSERT INTO @DASHBOARD_LOOKUP (GADGETFILE, GADGETTYPE, OLDGADGETSEQ, DEFAULT_TITLE) VALUES 
('UnprintedDocuments.ascx', 12, 1014, 'Unprinted Point Documents'),
('EmployeeSeniorityListing.ascx', 13, 1011, 'Employee Seniority'),
('UserReports.ascx', 14, 1015, 'User Reports'),
('TimeoffRequestCount.ascx', 15, 1004, 'Timeoff Request'),
('ExceptionCount.ascx', 16, 1003, 'Exception Summary'),
('PushDeviceStatus.ascx', 20, 1007, 'Push Device Status'),
('Attendance_PointSystem.ascx', 24, 1012, 'Point Balance'),
('TimeoffRequestApproval.ascx', 27, 1017, 'Timeoff Request Approval'),
('FMLA_Active_Cases.ascx', 29, 1019, 'FMLA Active Cases'),
('ASM_Status.ascx', 31, 1021, 'Advanced Schedule Rule Status'),
('ApproachingOvertimeII.ascx', 30, 1020, 'Approaching Overtime')

------------------------------- BEGIN ACCESS Table -------------------------------
INSERT INTO @TEMP_DT(SEQ, MDASHBOARD, CDASHBOARD)
SELECT SEQ, MDASHBOARD, CDASHBOARD FROM A_ACCESS
inner join a_partypartyrel on a_access.seq = A_PARTYPARTYREL.seqa and a_partypartyrel.TYPESEQ=1003 and a_partypartyrel.seqb <> 1001
and (CAST(MDASHBOARD AS VARCHAR) <> '' OR CAST(CDASHBOARD AS VARCHAR) <> '')

WHILE EXISTS (SELECT top 1 null FROM @TEMP_DT)
BEGIN
    DELETE FROM @CDASHBOARD_VALUES_TBL
    DELETE FROM @OLDGADGET_SEQ_TBL
    
    SELECT TOP 1 @SEQ = SEQ, @MDASHBOARD=MDASHBOARD, @CDASHBOARD=CDASHBOARD, @XML = MDASHBOARD FROM @TEMP_DT

    -- Get gadget configurations from the xml
    insert into @legacy_gadget_config (gadgetType, title)
    select replace(gadget.value('@gadgetType', 'varchar(max)'), 'Gadget%5c', '') gadgetType
    , gadget.value('Title[1]', 'varchar(max)') title
    from @XML.nodes('/Batch/dropZone/gadget') as x(gadget)

    IF @CDASHBOARD <> ''
    BEGIN
        -- Splitting CDASHBOARD using xml
        SET @TEMP_XML = CONVERT(xml, '<root><myvalue>' 
            + REPLACE(@CDASHBOARD, @config_separator, '</myvalue><myvalue>') + '</myvalue></root>')

        -- Get gadget list from CDASHBOARD, empty means all gadgets    
        INSERT INTO @CDASHBOARD_VALUES_TBL
        SELECT T.parts.value('.', 'varchar(max)')
        FROM @TEMP_XML.nodes('(/root/myvalue)') T(parts)
    END

    SET @OLDGADGET_SEQ_STR = (SELECT TOP 1 ALL_PARTS from @CDASHBOARD_VALUES_TBL)

    IF @OLDGADGET_SEQ_STR <> ''
    BEGIN
        -- Splitting the gadget using xml
        SET @TEMP_XML =  CONVERT(xml,'<root><myvalue>' 
            + REPLACE(@OLDGADGET_SEQ_STR, @comma, '</myvalue><myvalue>') + '</myvalue></root>')

        INSERT INTO @OLDGADGET_SEQ_TBL
        SELECT T.parts.value('.', 'int') 
        FROM @TEMP_XML.nodes('/root/myvalue') T(parts)
    END
    ELSE
    BEGIN
        BEGIN
            INSERT INTO @OLDGADGET_SEQ_TBL
            SELECT OLDGADGETSEQ FROM @DASHBOARD_LOOKUP
        END
    END

    SET @json_gadget_string = ''

    WHILE EXISTS(SELECT TOP 1 NULL FROM @OLDGADGET_SEQ_TBL)
    BEGIN
        SET @OLDGADGET_SEQ = (SELECT TOP 1 seq FROM @OLDGADGET_SEQ_TBL)

        IF @OLDGADGET_SEQ IS NOT NULL
        BEGIN        
            set @OLDGADGET_TYPE = (select top 1 GADGETFILE from @DASHBOARD_LOOKUP where OLDGADGETSEQ = @OLDGADGET_SEQ)
                
            if @OLDGADGET_TYPE IS NOT NULL
            begin
                set @gadgetType = (select top 1 gadgetType from @legacy_gadget_config where gadgetType = @OLDGADGET_TYPE)
                set @newGadgetType = (select top 1 GADGETTYPE from @DASHBOARD_LOOKUP where GADGETFILE = @OLDGADGET_TYPE)

                if @gadgetType is null
                begin
                    set @ExternalTitle = (select top 1 DEFAULT_TITLE from @DASHBOARD_LOOKUP where GADGETFILE = @OLDGADGET_TYPE)
                end
                else
                begin
                    set @ExternalTitle = (select top 1 title from @legacy_gadget_config where gadgetType = @OLDGADGET_TYPE)
                end

                -- Create new gadget object json string
                set @json_gadget_string += case when @json_gadget_string = '' then '' else @comma end 
                    + @Id_prop + cast(@newGadgetType as varchar)
                    + @GadgetType_prop + cast(@newGadgetType as varchar)
                    + @ExternalTitle_prop + @ExternalTitle
                    + case when (@gadgetType is null or @gadgetType = 1017) AND @MDASHBOARD <> '' then @DisplayFalse_prop else @Display_prop end

                delete @legacy_gadget_config where gadgetType = @OLDGADGET_TYPE
            end
        END

        DELETE @OLDGADGET_SEQ_TBL WHERE SEQ = @OLDGADGET_SEQ
    END

    -- Check if the entry in the MDASHBOARD is xml format. If yes we will update the CDASHBOARD with the entry
    if exists (select top 1 null from (select batch.query('.') as x from @XML.nodes('/Batch') as x(batch)) t) OR @MDASHBOARD = ''
    begin
        IF @CDASHBOARD = ''
        BEGIN
           UPDATE A_ACCESS SET CDASHBOARD='||0||1||0||30_30_30||' + @MDASHBOARD  WHERE SEQ = @SEQ
        END
        ELSE
        BEGIN
            UPDATE A_ACCESS SET CDASHBOARD=cast(CDASHBOARD as nvarchar(max)) + '||' + @MDASHBOARD  WHERE SEQ = @SEQ
        END

        if @json_gadget_string <> ''
        begin
            update A_ACCESS
            set MDASHBOARD = @json_begin + @json_gadget_string + @json_end
            where SEQ = @SEQ
        end
        else
        begin
            update A_ACCESS
            set MDASHBOARD = ''
            where SEQ = @SEQ
        end
    end

    DELETE FROM @TEMP_DT WHERE SEQ = @SEQ
END
------------------------------- END ACCESS Table -------------------------------


------------------------------- BEGIN USERS Table -------------------------------
INSERT INTO @TEMP_DT(SEQ, MDASHBOARD, CDASHBOARD)
SELECT IID, MDASHBOARD, CDASHBOARD FROM USERS
WHERE CAST(MDASHBOARD AS varchar) <> ''

WHILE EXISTS (SELECT top 1 null FROM @TEMP_DT)
BEGIN
    SELECT TOP 1 @SEQ = SEQ, @MDASHBOARD=MDASHBOARD, @CDASHBOARD=CDASHBOARD, @XML = MDASHBOARD FROM @TEMP_DT

    insert into @legacy_gadget_config (gadgetType, title)
    select replace(gadget.value('@gadgetType', 'varchar(max)'), 'Gadget%5c', '') gadgetType
    , gadget.value('Title[1]', 'varchar(max)') title
    from @XML.nodes('Batch/dropZone/gadget') as x(gadget)

    set @json_gadget_string = ''
              
    WHILE EXISTS (SELECT top 1 null FROM @legacy_gadget_config)
    begin
        set @ExternalTitle = ''

        select top 1 @gadgetType = gadgetType, @ExternalTitle = title from @legacy_gadget_config
                     
        set @newGadgetType = (select GADGETTYPE from @DASHBOARD_LOOKUP where GADGETFILE = @gadgetType)

        if @newGadgetType is not null
        begin
            -- Create new gadget object json string
            set @json_gadget_string += case when @json_gadget_string = '' then '' else @comma end 
                + @Id_prop + cast(@newGadgetType as varchar)
                + @GadgetType_prop + cast(@newGadgetType as varchar)
                + @ExternalTitle_prop + @ExternalTitle
                + case when @newGadgetType = 27 then @DisplayFalse_prop else @Display_prop end
        end

        delete from @legacy_gadget_config where gadgetType = @gadgetType
    end

    if @json_gadget_string <> ''
    begin
        -- INSERT only if the record is not exist
        if not exists (SELECT top 1 null from PREFERENCE WHERE IUSERSEQ = @SEQ)
        begin
            INSERT INTO PREFERENCE (IEMPSEQ, IUSERSEQ, MDASHBOARD) VALUES (-1, @SEQ, @json_begin + @json_gadget_string + @json_end)
        end
    end

    DELETE FROM @TEMP_DT WHERE SEQ = @SEQ
END
------------------------------- END USERS Table -------------------------------

ROLLBACK