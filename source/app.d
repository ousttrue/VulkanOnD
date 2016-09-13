version = DVulkanAllExtensions;

import logger;
import derelict.glfw3.glfw3;
mixin DerelictGLFW3_WindowsBind;
import dvulkan;
import std.experimental.logger;
import std.exception;
import std.algorithm;
import std.range;
import std.conv;
import std.traits;
import std.file;
import core.sys.windows.windows;
import core.stdc.string;
import gfm.math;


immutable NUM_DESCRIPTOR_SETS=1;
immutable NUM_SAMPLES=VK_SAMPLE_COUNT_1_BIT;
/* Amount of time, in nanoseconds, to wait for a command buffer to complete */
immutable FENCE_TIMEOUT = 100000000;


struct VkWin32SurfaceCreateInfoKHR
{
	VkStructureType sType = VkStructureType.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
	const(void)* pNext;
	VkFlags flags;
	HINSTANCE hinstance;
	HWND hwnd;
};
void create_swapchain(VkInstance inst, VkSurfaceKHR *surface, HINSTANCE hinstance, HWND hwnd)
{
	alias PFN_vkCreateWin32SurfaceKHR
		= extern(C) VkResult function(VkInstance instance,
										const(VkWin32SurfaceCreateInfoKHR)* pCreateInfo
											, const(VkAllocationCallbacks)* pAllocator
												,VkSurfaceKHR* pSurface);
	auto p=vkGetInstanceProcAddr(inst, "vkCreateWin32SurfaceKHR");
	auto  vkCreateWin32SurfaceKHR
		= cast(PFN_vkCreateWin32SurfaceKHR) p;
	enforce(vkCreateWin32SurfaceKHR, "vkGetInstanceProcAddr vkCreateWin32SurfaceKHR");

	// Construct the surface description:
	VkWin32SurfaceCreateInfoKHR createInfo = {
		//hinstance: hinstance,
	hwnd: hwnd,
	};

	auto res = vkCreateWin32SurfaceKHR(inst,
										&createInfo,
										null, surface);
}


struct Glfw3Manager
{
	GLFWwindow *window;

	static this()
	{
		log("DerelictGLFW3.load.");
		DerelictGLFW3.load();
		DerelictGLFW3_loadWindows();
	}

	~this()
	{
		log("~Glfw3Manager");
		glfwTerminate();
	}

	HWND get_hwnd()
	{
		return glfwGetWin32Window(window);
	}

	bool initialize()
	{
		glfwInit();
		const window_width  = 800;
		const window_height = 600;
		window = glfwCreateWindow(window_width, window_height
								  , "VulkanOnD"
								  , null, null);
		log("create window.");

		return true;
	}

	bool newFrame()
	{
		if(glfwWindowShouldClose(window)){
			return false;
		}
		glfwPollEvents();
		return true;
	}
}


void main()
{
	// logger
    auto defaultFileLogger=cast(FileLogger)sharedLog;
    sharedLog = new MyCustomLogger(defaultFileLogger);

	Glfw3Manager glfw;
	if(!glfw.initialize()){
		return;
	}
	log("glfw.initialized");

	//create_swapchain(GetModuleHandle(null), glfw.get_hwnd());

	while(glfw.newFrame()){
		//
	}
}
