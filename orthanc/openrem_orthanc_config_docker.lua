-------------------------------------------------------------------------------------
-- OpenREM python environment and other settings
-- This file has been configured for Docker use and should not normally be edited.
-- See the documentation for details

-- Set this to the path where you want Orthanc to temporarily store DICOM files
local temp_path = '/imports/'

-- Set this to 'mkdir' on Windows, or 'mkdir -p' on Linux
local mkdir_cmd = 'mkdir -p'

-- Set this to '\\'' on Windows, or '/' on Linux
local dir_sep = '/'

-- Set this to true if you want Orthanc to keep physics test studies, and have it
-- put them in the physics_to_keep_folder. Set it to false to disable this feature
local use_physics_filtering_val = os.getenv("USE_PHYSICS_FILTERING")
if use_physics_filtering_val == 'true' then use_physics_filtering = true
else use_physics_filtering = false end

-- Set this to the path where you want to keep physics-related DICOM images
local physics_to_keep_folder = '/imports/physics/'

-- Set this to the path and name of your zip utility, and include any switches that
-- are needed to create an archive and include all files in a supplied folder
-- (used with physics-related images)
local zip_executable = '/usr/bin/zip -r'

-- Set this to the path and name of your remove folder command, including switches
-- for it to be quiet (used with physics-related images)
local rmdir_cmd = 'rm -r'
-------------------------------------------------------------------------------------


-------------------------------------------------------------------------------------
-- User-defined lists that determine how Orthanc deals with certain studies

-- A list to check against patient name and ID to see if the images should be kept.
-- Orthanc will put anything that matches this in the physics_to_keep_folder.
local physics_to_keep_val = os.getenv("PHYSICS_TO_KEEP")
if physics_to_keep_val == "" or physics_to_keep_val == nil then physics_to_keep = {}
else load("physics_to_keep = " .. physics_to_keep_val)() end


-- Lists of things to ignore. Orthanc will ignore anything matching the content of
-- these lists: they will not be imported into OpenREM.
local manufacturers_to_ignore_val = os.getenv("MANUFACTURERS_TO_IGNORE")
local model_names_to_ignore_val = os.getenv("MODEL_NAMES_TO_IGNORE")
local station_names_to_ignore_val = os.getenv("STATION_NAMES_TO_IGNORE")
local software_versions_to_ignore_val = os.getenv("SOFTWARE_VERSIONS_TO_IGNORE")
local device_serial_numbers_to_ignore_val = os.getenv("DEVICE_SERIAL_NUMBERS_TO_IGNORE")
if manufacturers_to_ignore_val == "" or manufacturers_to_ignore_val == nil then manufacturers_to_ignore = {}
else load("manufacturers_to_ignore = " .. manufacturers_to_ignore_val)() end
if model_names_to_ignore_val == "" or model_names_to_ignore_val == nil then model_names_to_ignore = {}
else load("model_names_to_ignore = " .. model_names_to_ignore_val)() end
if station_names_to_ignore_val == "" or station_names_to_ignore_val == nil then station_names_to_ignore = {}
else load("station_names_to_ignore = " .. station_names_to_ignore_val)() end
if software_versions_to_ignore_val == "" or software_versions_to_ignore_val == nil then software_versions_to_ignore = {}
else load("software_versions_to_ignore = " .. software_versions_to_ignore_val)() end
if device_serial_numbers_to_ignore_val == "" or device_serial_numbers_to_ignore_val == nil then
    device_serial_numbers_to_ignore = {}
else load("device_serial_numbers_to_ignore = " .. device_serial_numbers_to_ignore_val)() end

-- Set this to true if you want to use the OpenREM Toshiba CT extractor. Set it to
-- false to disable this feature.
local use_toshiba_ct_extractor_val = os.getenv("USE_TOSHIBA_CT_EXTRACTOR")
if use_toshiba_ct_extractor_val == "true" then use_toshiba_ct_extractor = true
else use_toshiba_ct_extractor = false end

-- A list of CT make and model pairs that are known to have worked with the Toshiba CT extractor.
-- You can add to this list, but you will need to verify that the dose data created matches what you expect.
local toshiba_extractor_systems_val = os.getenv("TOSHIBA_EXTRACTOR_SYSTEMS")
if toshiba_extractor_systems_val == "" or toshiba_extractor_systems_val == nil then
    toshiba_extractor_systems = {
        {'Toshiba', 'Aquilion'},
        {'GE Medical Systems', 'Discovery STE'},
    }
else load("toshiba_extractor_systems = " .. toshiba_extractor_systems_val)() end

-------------------------------------------------------------------------------------
-- Section above this point configured specifically for Docker installation
-------------------------------------------------------------------------------------

-- set virtual director to empty string if not defined
local virtual_directory_val = os.getenv("VIRTUAL_DIRECTORY")
if virtual_directory_val == nil then
    virtual_directory_val = ""
end

-------------------------------------------------------------------------------------

function ToAscii(s)
   -- http://www.lua.org/manual/5.1/manual.html#pdf-string.gsub
   -- https://groups.google.com/d/msg/orthanc-users/qMLgkEmwwPI/6jRpCrlgBwAJ
   return s:gsub('[^a-zA-Z0-9-/-:-\\ ]', '_')
end


function ReceivedInstanceFilter(dicom)
    -- Only allow incoming objects we can use, plus XA and RF to enable physics filtering with XA/RF images
    local mod = dicom.Modality
    if (mod ~= 'SR') and (mod ~= 'CT') and (mod ~= 'MG') and (mod ~= 'CR') and (mod ~= 'DX') and (mod ~= 'PX') and (mod ~= 'PT') and (mod ~= 'NM') and (mod ~= 'XA') and (mod ~= 'RF') then
        return false
    else
        return true
    end
end


function OnStoredInstance(instanceId)
    print('Starting OnStoredInstance')

    -- Retrieve the DICOM tags from the instance. The tags parameter doesn't include all the useful
    -- tags - this does.
    local instance_tags = ParseJson(RestApiGet('/instances/' .. instanceId .. '/simplified-tags'))


    -------------------------------------------------------------------------------------
    -- See if the images are physics tests - if so, keep them and exit this function
    print('Is it a physics test?')
    if use_physics_filtering == true then
        if instance_tags.PatientName ~= nil then
            for i = 1, #physics_to_keep do
                if string.match(string.lower(instance_tags.PatientName), string.lower(physics_to_keep[i])) then
                    print('Yes, it is a physics test')
                    return true
                end
            end
        end
        if instance_tags.PatientID ~= nil then
            for i = 1, #physics_to_keep do
                if string.match(string.lower(instance_tags.PatientID), string.lower(physics_to_keep[i])) then
                    print('Yes, it is a physics test')
                    return true
                end
            end
        end
    end
    -------------------------------------------------------------------------------------


    -------------------------------------------------------------------------------------
    -- If the instance matches something in one of the "ignore" lists then remove the file
    -- and do not import it into Orthanc
    if instance_tags.Manufacturer ~= nil then
        for i = 1, #manufacturers_to_ignore do
            print('Checking against: ' .. manufacturers_to_ignore[i])
            if string.lower(instance_tags.Manufacturer) == string.lower(manufacturers_to_ignore[i]) then
                print('They match - ignoring ' .. instance_tags.Manufacturer)
                Delete(instanceId)
                return true
            end
        end
    end

    if instance_tags.ManufacturerModelName ~= nil then
        for i = 1, #model_names_to_ignore do
            print('Checking against: ' .. model_names_to_ignore[i])
            if string.lower(instance_tags.ManufacturerModelName) == string.lower(model_names_to_ignore[i]) then
                print('Ignoring ' .. instance_tags.ManufacturerModelName)
                Delete(instanceId)
                return true
            end
        end
    end

    if instance_tags.StationName ~= nil then
        for i = 1, #station_names_to_ignore do
            print('Checking against: ' .. station_names_to_ignore[i])
            if string.lower(instance_tags.StationName) == string.lower(station_names_to_ignore[i]) then
                print('Ignoring ' .. instance_tags.StationName)
                Delete(instanceId)
                return true
            end
        end
    end

    if instance_tags.SoftwareVersions ~= nil then
        for i = 1, #software_versions_to_ignore do
            print('Checking against: ' .. software_versions_to_ignore[i])
            if string.lower(instance_tags.SoftwareVersions) == string.lower(software_versions_to_ignore[i]) then
                print('Ignoring ' .. instance_tags.SoftwareVersions)
                Delete(instanceId)
                return true
            end
        end
    end

    if instance_tags.DeviceSerialNumber ~= nil then
        for i = 1, #device_serial_numbers_to_ignore do
            print('Checking against: ' .. device_serial_numbers_to_ignore[i])
            if string.lower(instance_tags.DeviceSerialNumber) == string.lower(device_serial_numbers_to_ignore[i]) then
                print('Ignoring ' .. instance_tags.DeviceSerialNumber)
                Delete(instanceId)
                return true
            end
        end
    end
    -- End of seeing if we should igore the instance
    -------------------------------------------------------------------------------------


    -------------------------------------------------------------------------------------
    -- Work out if file can be used by the RDSR, MG, DX or ctphilips extractors
    local import_script = ''
    if instance_tags.SOPClassUID ~= nil then
        if instance_tags.SOPClassUID == '1.2.840.10008.5.1.4.1.1.88.67' then
            import_script = 'rdsr'
        elseif instance_tags.SOPClassUID == '1.2.840.10008.5.1.4.1.1.88.22' then
            -- Enhanced SR used by GE CT Scanners
            import_script = 'rdsr'
        elseif instance_tags.SOPClassUID == '1.2.840.10008.5.1.4.1.1.88.68' then
            -- Radiopharmaceutical radiation dose SR
            import_script = 'rdsr'
        end
    end
    if (instance_tags.Modality ~= nil) and (import_script == '') then
        if instance_tags.Modality == 'MG' then
            import_script = 'mam'
        elseif (instance_tags.Modality == 'CR') or (instance_tags.Modality == 'DX') or (instance_tags.Modality == 'PX') then
            import_script = 'dx'
        elseif (instance_tags.Modality == 'PT') or (instance_tags.Modality == 'NM') then
            import_script = 'nm'
        end
    end
    if (instance_tags.SOPClassUID ~= nil) and (instance_tags.Manufacturer ~= nil) and (import_script == '') then
        if (instance_tags.SOPClassUID == '1.2.840.10008.5.1.4.1.1.7') and string.match(string.lower(instance_tags.Manufacturer), 'philips') then
            -- Secondary Capture object that might be Philips CT Dose Info image
            import_script = 'ct_philips'
        end
    end
    -------------------------------------------------------------------------------------


    -------------------------------------------------------------------------------------
    -- Work out if the Toshiba CT extractor should be used - must be CT and a match with
    -- a make/model pair in toshiba_extractor_systems
    local toshiba_extractor_match = false

    if use_toshiba_ct_extractor == true then
        if import_script == '' then
            if (instance_tags.Manufacturer == nil) or (instance_tags.ManufacturerModelName == nil) then
                -- If the Manufacturer or ManufacturerModelName is nil then the Toshiba check cannot be made
                print('Rejecting DICOM instance because one of both of Manufacturer or ManufacturerModelName tag are nil: ' .. instanceId)
                -- Delete the DICOM instance and exit the function
                Delete(instanceId)
                return true
            end
            for i = 1, #toshiba_extractor_systems do
                if (instance_tags.Modality == 'CT')
                      and (string.lower(instance_tags.Manufacturer) == string.lower(toshiba_extractor_systems[i][1]))
                      and (string.lower(instance_tags.ManufacturerModelName) == string.lower(toshiba_extractor_systems[i][2])) then
                    -- Might be useful Toshiba import, leave it in the database until the study has finished importing
                    print('I am going to use the Toshiba CT extractor on this study')
                    toshiba_extractor_match = true
                    return true
                end
            end
        end
    end
    -------------------------------------------------------------------------------------


    -------------------------------------------------------------------------------------
    -- If we're not using the Toshiba CT extractor and import_script is empty then we
    -- don't know how to deal with this DICOM file - delete the instance from Orthanc and
    -- exit the function.
    if (toshiba_extractor_match == false) and (import_script == '') then
        -- Log the SOP Class UID, modality, make, model, software version and station name
        -- See http://dicom.nema.org/dicom/2013/output/chtml/part04/sect_B.5.html for a list
        -- of standard SOP classes
        local reject_msg = 'Rejecting a DICOM instance'
        if instance_tags.SOPClassUID           ~= nil then reject_msg = reject_msg .. ': SOPClassUID: '           .. instance_tags.SOPClassUID           end
        if instance_tags.Modality              ~= nil then reject_msg = reject_msg .. '; Modality: '              .. instance_tags.Modality              end
        if instance_tags.Manufacturer          ~= nil then reject_msg = reject_msg .. '; Manufacturer: '          .. instance_tags.Manufacturer          end
        if instance_tags.ManufacturerModelName ~= nil then reject_msg = reject_msg .. '; ManufacturerModelName: ' .. instance_tags.ManufacturerModelName end
        if instance_tags.SoftwareVersions      ~= nil then reject_msg = reject_msg .. '; SoftwareVersions: '      .. instance_tags.SoftwareVersions      end
        if instance_tags.StationName           ~= nil then reject_msg = reject_msg .. '; StationName: '           .. instance_tags.StationName           end
        print(reject_msg)
        Delete(instanceId)
        return true
    end
    -------------------------------------------------------------------------------------


    -------------------------------------------------------------------------------------
    -- If we've got this far then we can import the instance into OpenREM and then delete
    -- it from Orthanc. First write the DICOM content to a temporary file
    local temp_file_path = temp_path .. instanceId .. '.dcm'
    local target = assert(io.open(temp_file_path, 'wb'))
    local dicom = RestApiGet('/instances/' .. instanceId .. '/file')
    target:write(dicom)
    target:close()

    -- Send DICOM object path (shared between orthanc and openrem) and import type to openrem container via nginx
    local headers = {
        ["Host"] = "nginx",
    }
    local post_data = 'dicom_path=' .. temp_file_path .. '&import_type=' .. import_script
    HttpPost('http://nginx/' .. virtual_directory_val .. 'import/from_docker/', post_data, headers)
    
    -- Removing temporary file is not allowed/necessary. If configured in the webinterface file will be deleted
    -- by openrem after import
    -- os.remove(temp_file_path)

    -- Remove study from Orthanc
    Delete(instanceId)
    -------------------------------------------------------------------------------------
end


function OnStableStudy(studyId)
    print('This study is now stable, writing its instances on the disk: ' .. studyId)

    -- Retrieve the shared DICOM tags from the study. The tags parameter doesn't include
    -- all the useful tags - this does
    local study_tags = ParseJson(RestApiGet('/studies/' .. studyId .. '/shared-tags?simplify'))

    -------------------------------------------------------------------------------------
    -- See if any of the physics strings are in patient name or ID. If they are then
    -- copy the image to the physics_to_keep_folder and then remove it from Orthanc
    if use_physics_filtering == true then
        local patient_name
        local patient_id
        local patient_folder = 'blank'
        if study_tags.PatientName ~= nil then
            print('PatientName is: ' .. study_tags.PatientName)
            patient_name = study_tags.PatientName
            patient_folder = patient_name
        else
            patient_name = 'blank'
        end
        if study_tags.PatientID ~= nil then
            print('PatientID is: ' .. study_tags.PatientID)
            patient_id = study_tags.PatientID
            if patient_folder == 'blank' then
                patient_folder = patient_id
            end
        else
            patient_id = 'blank'
        end

        for i = 1, #physics_to_keep do
            if string.match(string.lower(patient_name), string.lower(physics_to_keep[i])) or string.match(string.lower(patient_id), string.lower(physics_to_keep[i])) then
                -- It is a physics patient - save them to the physics folder
                print('It is physics')
                local first_series = true
                local temp_files_path = ''

                -- Retrieve the IDs of all the series in this study
                local series = ParseJson(RestApiGet('/studies/' .. studyId)) ['Series']

                -- using _ as a placeholder as I'm not interested in the key value
                for _, current_series in pairs(series) do

                    if first_series == true then
                        -- Create a string containing the folder path.
                        temp_files_path = ToAscii(physics_to_keep_folder .. study_tags.StudyDate .. dir_sep .. patient_folder)
                        -- print('temp_files_path is: ' .. temp_files_path)

                        -- Create the folder
                        os.execute(mkdir_cmd .. ' "' .. temp_files_path .. '"')
                        -- print('Just tried to create folder: ' .. mkdir_cmd .. ' "' .. temp_files_path .. '"')

                        first_series = false
                    end

                    local instances = ParseJson(RestApiGet('/series/' .. current_series)) ['Instances']

                    -- Loop through each instance in the current_series
                    -- using _ as a placeholder as I'm not interested in the key value
                    for _, instance in pairs(instances) do
                        -- Retrieve the DICOM file from Orthanc
                        local dicom = RestApiGet('/instances/' .. instance .. '/file')

                        -- Write the DICOM file to the folder created earlier
                        local target = assert(io.open(temp_files_path .. dir_sep .. instance .. '.dcm', 'wb'))
                        -- print('Trying to write file: ' .. temp_files_path .. dir_sep .. instance .. '.dcm')
                        target:write(dicom)
                        target:close()

                        -- Remove the instance from Orthanc
                        Delete(instance)
                    end
                end

                -- Zip the study files to save space and remove the originals after zipping
                print('Zipping physics images: ' .. zip_executable .. ' "' .. temp_files_path .. '.zip"' .. ' "' .. temp_files_path .. dir_sep .. '"')
                os.execute(zip_executable .. ' "' .. temp_files_path .. '.zip"' .. ' "' .. temp_files_path .. dir_sep .. '"')
                print('Removing physics study folder: ' .. rmdir_cmd .. ' "' .. temp_files_path .. '"')
                os.execute(rmdir_cmd .. ' "' .. temp_files_path .. '"')

                -- Exit the function, as a physics study was found and the images moved
                return true

            end
        end
    end
    -------------------------------------------------------------------------------------


    -------------------------------------------------------------------------------------
    -- Use the CT Toshiba extractor on the study if the manufacturer and model are in the
    -- toshiba_extractor_systems list.
    if use_toshiba_ct_extractor == true then
        if (study_tags.Manufacturer == nil) or (study_tags.ManufacturerModelName == nil) then
            -- If the Manufacturer or ManufacturerModelName is nil then the Toshiba check cannot be made
            print('Rejecting DICOM study because one of both of Manufacturer or ManufacturerModelName tag are nil: ' .. studyId)
            -- Delete the study and exit the function
            Delete(studyId)
            return true
        end

        for i = 1, #toshiba_extractor_systems do
            local first_series
            local temp_files_path
            if (study_tags.Modality == 'CT')
                  and (string.lower(study_tags.Manufacturer) == string.lower(toshiba_extractor_systems[i][1]))
                  and (string.lower(study_tags.ManufacturerModelName) == string.lower(toshiba_extractor_systems[i][2])) then

                first_series = true
                temp_files_path = ''

                -- Retrieve the IDs of all the series in this study
                local series = ParseJson(RestApiGet('/studies/' .. studyId)) ['Series']

                -- using _ as a placeholder as I'm not interested in the key value
                for _, current_series in pairs(series) do

                    if first_series == true then
                        -- Create a string containing the folder path. This needs to be a single folder so that the Toshiba CT extractor
                        -- is able to remove it once the data has been imported into OpenREM.
                        temp_files_path = ToAscii(temp_path .. study_tags.StudyDate .. '_' .. study_tags.PatientID .. '_' .. studyId)
                        -- print('temp_files_path is: ' .. temp_files_path)

                        -- Create the folder
                        os.execute(mkdir_cmd .. ' "' .. temp_files_path .. '"')
                        -- print('Just tried to create folder: ' .. mkdir_cmd .. ' "' .. temp_files_path .. '"')

                        first_series = false
                    end

                    -- Obtain a table of instances in the series
                    local instances = ParseJson(RestApiGet('/series/' .. current_series)) ['Instances']

                    -- Loop through each instance
                    -- using _ as a placeholder as I'm not interested in the key value
                    for _, instance in pairs(instances) do
                        -- Retrieve the DICOM file from Orthanc
                        local dicom = RestApiGet('/instances/' .. instance .. '/file')

                        -- Write the DICOM file to the folder created earlier
                        local target = assert(io.open(temp_files_path .. dir_sep .. instance .. '.dcm', 'wb'))
                        -- print('Trying to write file: ' .. temp_files_path .. dir_sep .. instance .. '.dcm')
                        target:write(dicom)
                        target:close()

                        -- Remove the instance from Orthanc
                        Delete(instance)
                    end
                end

                -- Run the Toshiba extractor on the folder. The extractor will remove the temp_files_path folder.
                -- print('Trying to run: ' .. python_executable.. ' ' .. python_scripts_path .. 'openrem_cttoshiba.py' .. ' ' .. temp_files_path)
--                os.execute(python_executable.. ' ' .. python_scripts_path .. 'openrem_cttoshiba.py' .. ' ' .. temp_files_path)

                -- Send DICOM object path (shared between orthanc and openrem) and import type to openrem container via nginx
                local headers = {
                    ["Host"] = "nginx",
                }
                local post_data = 'dicom_path=' .. temp_files_path .. '&import_type=ct_toshiba'
                HttpPost('http://nginx/' .. virtual_directory_val .. 'import/from_docker/', post_data, headers)

                -- Exit the function
                return true
            end
        end
    end
    -------------------------------------------------------------------------------------

 end

function Initialize()
end
