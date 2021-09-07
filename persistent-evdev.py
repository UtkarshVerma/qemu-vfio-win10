#!/bin/python -u

import evdev
import os
import sys
import json
import selectors
import pyudev
import errno


class Device:
    def __init__(self):
        self.state = None
        self.name = None
        self.path = None
        self.evdev = None
        self.uinput = None
        self.capabilities = None


    def open_evdev(self):
        assert(self.evdev == None)

        self.evdev = evdev.InputDevice(self.path)

        print("opened evdev: %s: %s" % (self.name, self.path))

        self.evdev.grab()

        self.capabilities = self.evdev.capabilities()
        del self.capabilities[evdev.ecodes.EV_SYN]
        
        self.save_capabilities()

        self.state.selector.register(self.evdev.fileno(), selectors.EVENT_READ, data = self)

    
    def close_evdev(self):
        self.state.selector.unregister(self.evdev.fileno())
        self.evdev.close()
        self.evdev = None

        print("closed evdev: %s: %s" % (self.name, self.path))

        if self.uinput != None:
            self.uinput.syn()


    def make_capabilities_path(self):
        return os.path.join(self.state.cache_path, self.name + ".json")


    def load_capabilities(self):
        capabilities_path = self.make_capabilities_path()

        try:
            with open(capabilities_path, "r") as file:
                capabilities = json.load(file)

            for key in list(capabilities.keys()):
                capabilities[int(key)] = capabilities[key]
                del capabilities[key]

            self.capabilities = capabilities

        except FileNotFoundError:
            pass
        

    def save_capabilities(self):
        capabilities_path = self.make_capabilities_path()

        with open(capabilities_path, "w+") as file:
            json.dump(self.capabilities, file)

    
    def open_uinput(self):
        assert(self.capabilities != None)
        self.uinput = evdev.UInput(self.capabilities, name=self.name)

        print("opened uinput", self.name)


class State:
    def __init__(self):
        self.devices = None
        self.cache_path = None


    def load_config(self, config_path):
        with open(config_path, "r") as file:
            config = json.load(file)

        assert(isinstance(config, dict))
        assert("devices" in config)
        assert("cache" in config)
        assert(isinstance(config["devices"], dict))
        assert(isinstance(config["cache"], str))

        for device_name, device_path in config["devices"].items():
            assert(isinstance(device_name, str))
            assert(isinstance(device_path, str))

        self.cache_path = os.path.expanduser(config["cache"])
        self.devices = [ ]

        for device_name, device_path in config["devices"].items():
            device = Device()
            device.state = self
            device.name = device_name
            device.path = device_path
            self.devices.append(device)
            print("config device:", device.name, device.path)


    def list_available_devices(self):
        available_evdev_devices = set()

        for evdev_device in evdev.list_devices():
            available_evdev_devices.add(os.path.realpath(evdev_device))

        for device in self.devices:
            device_realpath = os.path.realpath(device.path)

            if device_realpath in available_evdev_devices:
                yield device


    def update_devices(self):
        for device in self.list_available_devices():
            if device.evdev == None:
                device.open_evdev()
        
        for device in self.devices:
            if device.capabilities == None:
                device.load_capabilities()

        for device in self.devices:
            if device.uinput == None and device.capabilities != None:
                device.open_uinput()


    def setup(self):
        self.selector = selectors.DefaultSelector()

        self.pyudev_context = pyudev.Context()
        self.pyudev_monitor = pyudev.Monitor.from_netlink(self.pyudev_context)
        self.pyudev_monitor.filter_by(subsystem='input')
        self.selector.register(self.pyudev_monitor.fileno(), selectors.EVENT_READ, data = self.pyudev_monitor)
        self.pyudev_monitor.start()
        

    def loop(self):
        while True:
            for key, mask in self.selector.select():
                if isinstance(key.data, Device):
                    device = key.data

                    i = None
                    
                    while True:
                        try:
                            if i == None:
                                i = device.evdev.read()
                            
                            event = next(i)

                        except StopIteration:
                            break

                        except OSError as err:
                            if err.errno == errno.ENODEV:
                                device.close_evdev()
                                break
                            else:
                                raise
                        
                        device.uinput.write_event(event)
                        #print("%s: %s" % (device.name, evdev.categorize(event)))
            
                elif key.data == self.pyudev_monitor:
                    detected_new_device = False

                    while True:
                        event = self.pyudev_monitor.poll(0)                        
                        
                        if event == None:
                            break

                        if event.action == 'add' and event.device_node != None:
                            detected_new_device = True                            
                
                    if detected_new_device:
                        self.update_devices()


def main(args):
    if len(args) != 2:
        print("syntax: %s config.json" % args[0])
        return 1
    
    state = State()
    state.setup()
    state.load_config(os.path.expanduser(args[1]))
    state.update_devices()
    state.loop()

    return 0


if __name__ == "__main__":
    ret = main(sys.argv)

    if ret != 0:
        exit(ret)
