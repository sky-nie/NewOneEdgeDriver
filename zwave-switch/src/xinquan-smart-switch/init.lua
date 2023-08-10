-- Copyright 2023 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=1 })
local log = require "log"
local ZWAVE_DUAL_SWITCH_FINGERPRINTS = {
  { mfr = 0x0312, prod = 0xFF00, model = 0xFF0E }, -- Mini Smart Plug Meter, MP21ZP
  { mfr = 0x0312, prod = 0xFF00, model = 0xFF0F }, -- Mini Smart Plug Meter, MP22ZP
  { mfr = 0x0312, prod = 0xFF00, model = 0xFF11 }, -- Mini Power Meter Plug, ZW38M
  { mfr = 0x0312, prod = 0xAC01, model = 0x4003 } -- Mini Power Meter Plug, N4003
}

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_DUAL_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

-- Despite the NIF indicating that this device supports the Switch Multilevel
-- command class, the device will not respond to multilevel commands. Note that
-- this applies at least to the Aeotec Smart Switch 6 and 7
local function on_off_factory(onOff)
  return function(driver, device, cmd)
    device:send(Basic:Set({value=onOff}))
    device.thread:call_with_delay(3, function() device:send(SwitchBinary:Get({})) end)
  end
end

local function calc_voltage(ADCvalue)
  local volt = (((1.5338*(10^-16))*(ADCvalue^5)) - ((1.2630*(10^-12))*(ADCvalue^4)) + ((3.8111*(10^-9))*(ADCvalue^3)) - ((4.7739*(10^-6))*(ADCvalue^2)) + ((2.8558*(10^-3))*(ADCvalue)) - (2.2721*(10^-2)))
  log.debug("calc_voltage: volt = ", volt)
  return volt
end

local function switch_report_handler(driver, device, cmd)
  local volt = calc_voltage(cmd.args.value)
  local evt = capabilities.voltageMeasurement.voltage({value=volt,unit="V"})
  log.debug("switch_report_handler:evt = ", evt)
  device:emit_event(evt)
end

local aeotec_smart_switch = {
  NAME = "Xinquan Smart Switch",
  zwave_handlers = {
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report_handler
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = switch_report_handler
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_off_factory(0xFF),
      [capabilities.switch.commands.off.NAME] = on_off_factory(0x00)
    }
  },
  can_handle = can_handle
}

return aeotec_smart_switch
