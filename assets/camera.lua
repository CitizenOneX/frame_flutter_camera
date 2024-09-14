-- Module to encapsulate taking and sending photos as simple frame app messages
_M = {}

-- Frame to phone flags
local IMAGE_MSG = 0x07
local IMAGE_FINAL_MSG = 0x08

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

function show_flash()
	frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
	frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

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

	show_flash()
	frame.camera.capture { quality_factor = quality }
	clear_display()
	-- wait until the capture is finished and the image is ready before continuing
	while not frame.camera.image_ready() do
		frame.sleep(0.05)
	end

	local bytes_sent = 0

	local data = ''

	while true do
        data = frame.camera.read_raw(frame.bluetooth.max_length() - 4)
        if (data ~= nil) then
            pcall(frame.bluetooth.send, string.char(IMAGE_MSG) .. data)
            bytes_sent = bytes_sent + string.len(data)
            frame.sleep(0.0125)
		else
            pcall(frame.bluetooth.send, string.char(IMAGE_FINAL_MSG))
            frame.sleep(0.0125)
            break
		end
	end
end

return _M