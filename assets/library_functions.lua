-- we store the data from the host quickly from the data handler interrupt
-- and wait for the main loop to pick it up for processing/drawing
-- app_data contains all camera settings settable from the UI
-- quality, exposure, metering mode, ...
local app_data = { quality = 50, auto_exp_gain_times = 0, metering_mode = "SPOT", exposure = 0, shutter_kp = 0.1, shutter_limit = 6000, gain_kp = 1.0, gain_limit = 248.0}
local take_photo = false
local quality_values = {10, 25, 50, 100}
local metering_values = {'SPOT', 'CENTER_WEIGHTED', 'AVERAGE'}

-- Frame to phone flags
BATTERY_LEVEL_FLAG = "\x0c"
NON_FINAL_CHUNK_FLAG = "\x07"
FINAL_CHUNK_FLAG = "\x08"

-- Phone to Frame flags
TAKE_PHOTO_FLAG = 0x0d

-- every time byte data arrives just extract the data payload from the message
-- and save to the local app_data table so the main loop can pick it up and print it
function data_handler(data)
    if string.byte(data, 1) == TAKE_PHOTO_FLAG then
        -- quality and metering mode are indices into arrays of values (0-based phoneside; 1-based in Lua)
        -- exposure maps from 0..255 to -2.0..+2.0
        app_data.quality = quality_values[string.byte(data, 2) + 1]
        app_data.auto_exp_gain_times = string.byte(data, 3)
        app_data.metering_mode = metering_values[string.byte(data, 4) + 1]
        app_data.exposure = (string.byte(data, 5) - 128) / 64.0
        app_data.shutter_kp = string.byte(data, 6) / 10.0
        app_data.shutter_limit = string.byte(data, 7) << 8 | string.byte(data, 8)
        app_data.gain_kp = string.byte(data, 9) / 10.0
        app_data.gain_limit = string.byte(data, 10)
		take_photo = true
    end
end

function camera_capture_and_send(args)
	quality = args.quality or 50
	auto_exp_gain_times = args.auto_exp_gain_times or 0
	metering_mode = args.metering_mode or 'SPOT'
	exposure = args.exposure or 0
	shutter_kp = args.shutter_kp or 0.1
	shutter_limit = args.shutter_limit or 6000
	gain_kp = args.gain_kp or 1.0
	gain_limit = args.gain_limit or 248.0
	print(quality)
	print(auto_exp_gain_times)
	print(metering_mode)
	print(exposure)
	print(shutter_kp)
	print(shutter_limit)
	print(gain_kp)
	print(gain_limit)

	for run=1,auto_exp_gain_times,1 do
		frame.camera.auto { metering = metering_mode, exposure = exposure, shutter_kp = shutter_kp, shutter_limit = shutter_limit, gain_kp = gain_kp, gain_limit = gain_limit }
		frame.sleep(0.1)
	end

	frame.camera.capture { quality_factor = quality }

	local chunkIndex = 0
	frame.sleep(0.5)
	local image_size = frame.fpga.read(0x21, 2)
	print(string.byte(image_size, 1) << 8 | string.byte(image_size, 2))

	while true do
		local data = frame.camera.read(frame.bluetooth.max_length() - 4)
		if (data == nil) then
			pcall(frame.bluetooth.send, FINAL_CHUNK_FLAG .. string.char(chunkIndex))
			break
		else
			pcall(frame.bluetooth.send, NON_FINAL_CHUNK_FLAG .. data)
			chunkIndex = chunkIndex + 1
			frame.sleep(0.02)
		end
	end
end

function send_batt_if_elapsed(prev, interval)
    local t = frame.time.utc()
    if ((prev == 0) or ((t - prev) > interval)) then
        pcall(frame.bluetooth.send, BATTERY_LEVEL_FLAG .. string.char(math.floor(frame.battery_level())))
        return t
    else
        return prev
    end
end

-- Main app loop
function app_loop()
    local last_batt_update = 0

	while true do
		if take_photo then
			take_photo = false

			pcall(camera_capture_and_send, app_data)
		end

        -- periodic battery level updates, 12s for a camera app
        last_batt_update = send_batt_if_elapsed(last_batt_update, 120)
		frame.sleep(0.1)
	end
end

-- register the handler as a callback for all data sent from the host
frame.bluetooth.receive_callback(data_handler)

-- run the main app loop
app_loop()