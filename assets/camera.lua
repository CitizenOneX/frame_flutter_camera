-- Module to encapsulate taking and sending photos as simple frame app messages
_M = {}

-- Frame to phone flags
local IMAGE_MSG = 0x07

function _M.camera_capture_and_send(args)
	quality = args.quality or 50
	auto_exp_gain_times = args.auto_exp_gain_times or 0
	metering_mode = args.metering_mode or 'SPOT'
	exposure = args.exposure or 0
	shutter_kp = args.shutter_kp or 0.1
	shutter_limit = args.shutter_limit or 6000
	gain_kp = args.gain_kp or 1.0
	gain_limit = args.gain_limit or 248.0

	for run=1,auto_exp_gain_times,1 do
		frame.camera.auto { metering = metering_mode, exposure = exposure, shutter_kp = shutter_kp, shutter_limit = shutter_limit, gain_kp = gain_kp, gain_limit = gain_limit }
		frame.sleep(0.1)
	end

	frame.camera.capture { quality_factor = quality }

	local first_chunk = true
	local image_size = 0
	local bytes_sent = 0

	-- keep polling the available bytes until it stabilizes for 0.1s
	local image_size = 0
	local prev_size = -1
	repeat
		frame.sleep(0.1)
		prev_size = image_size
		image_size = frame.fpga.read(0x21, 2)
	until (image_size == prev_size and image_size ~= 0)

	local data = ''

	while true do
		if first_chunk then
			first_chunk = false
			data = frame.camera.read_raw(frame.bluetooth.max_length() - 6)
			if (data ~= nil) then
				pcall(frame.bluetooth.send, string.char(IMAGE_MSG) .. string.char(string.byte(image_size, 1)) .. string.char(string.byte(image_size, 2)) .. data)
				bytes_sent = bytes_sent + string.len(data)
				frame.sleep(0.02)
			end
		else
			data = frame.camera.read_raw(frame.bluetooth.max_length() - 4)
			if (data == nil) then
				break
			else
				pcall(frame.bluetooth.send, string.char(IMAGE_MSG) .. data)
				bytes_sent = bytes_sent + string.len(data)
				frame.sleep(0.02)
			end
		end
	end
end

return _M