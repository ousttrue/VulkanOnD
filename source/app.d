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
import core.sys.windows.windows;


struct VulkanManager
{
    VkInstance inst;
    VkPhysicalDevice[] gpus;
	VkQueueFamilyProperties[] queue_props;
	int queue_family_index=-1;
	VkDevice device;
	VkCommandPool cmd_pool;
	VkCommandBuffer cmd;
	VkSurfaceKHR surface;
	VkSwapchainKHR swap_chain;
	struct swap_chain_buffer
	{
		VkImage image;
		VkImageView view;
	};
	swap_chain_buffer[] buffers;

	static this()
	{
		log("DVulkanDerelict.load.");
		DVulkanDerelict.load();
		DVulkanDerelict.loadInitializationFunctions();
	}

    ~this()
    {
		log("~VulkanManager");
		vkDestroyDevice(device, null);
        vkDestroyInstance(inst, null);
    }

    bool initialize(HINSTANCE hinstance, HWND hwnd)
    {
		// 01-init_instance
        {
            // initialize the VkApplicationInfo structure
            VkApplicationInfo app_info = {
			pApplicationName: "VulkanOnD",
			apiVersion: VK_MAKE_VERSION(1, 0, 0),
            };

            // initialize the VkInstanceCreateInfo structure
			auto extensions=[ 
				to!string(VK_KHR_SURFACE_EXTENSION_NAME),
				"VK_KHR_win32_surface",
			];
			auto extensionPtrs = extensions.map!("a.ptr").array;
            VkInstanceCreateInfo inst_info = {
			pApplicationInfo: &app_info,

			enabledExtensionCount: extensionPtrs.length,
			ppEnabledExtensionNames: extensionPtrs.ptr,
            };

            auto res = vkCreateInstance(&inst_info, null, &inst);
            if (res != VkResult.VK_SUCCESS){
                if(res == VkResult.VK_ERROR_INCOMPATIBLE_DRIVER) {
                    error("cannot find a compatible Vulkan ICD");
                    return false;
                }
                else  {
                    error("unknown error");
                    return false;
                }
            }

            loadInstanceFunctions(inst);
            enforce(vkDestroyInstance, "loadInstanceFunctions");
			info("01-init_instance");
        }

		// 02-enumerate_devices
        {
            uint gpu_count = 1;
            auto res =
                vkEnumeratePhysicalDevices(inst, &gpu_count, null);
            enforce(gpu_count, "gpu_count");

            gpus=new VkPhysicalDevice[gpu_count];
            res = vkEnumeratePhysicalDevices(inst, &gpu_count, gpus.ptr);
            enforce(!res && gpu_count >= 1, "vkEnumeratePhysicalDevices");
			info("02-enumerate_devices");
        }

		// 03-init_device
		{
			uint queue_family_count;
			vkGetPhysicalDeviceQueueFamilyProperties(gpus[0],
													 &queue_family_count, null);
			enforce(queue_family_count >= 1, "vkGetPhysicalDeviceQueueFamilyProperties");

			queue_props=new VkQueueFamilyProperties[queue_family_count];
			vkGetPhysicalDeviceQueueFamilyProperties(
													 gpus[0], &queue_family_count, queue_props.ptr);
			enforce(queue_family_count >= 1);

			queue_family_index = -1;
			for(int i=0; i<queue_props.length; ++i)
			{
				if(queue_props[i].queueFlags & VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT){
					queue_family_index=i;
					break;
				}
			}
			enforce(queue_family_index>= 0);

			/*
			VkDeviceQueueCreateInfo queue_info={
			queueCount: 1,
			pQueuePriorities: [0.0f],
			};

			auto names=[ to!string(VK_KHR_SWAPCHAIN_EXTENSION_NAME) ];
			auto device_extension_names=names.map!("a.ptr").array;
			VkDeviceCreateInfo device_info = {
			queueCreateInfoCount: 1,
			pQueueCreateInfos: &queue_info,

			enabledExtensionCount: device_extension_names.length,
			ppEnabledExtensionNames: device_extension_names.ptr,
			};

			auto res =
				vkCreateDevice(gpus[0], &device_info, null, &device);
			enforce(res == VkResult.VK_SUCCESS, "vkCreateDevice");
			*/

			info("03-init_device");
		}

		/+
		// 04-init_command_buffer
		{
			/* Create a command pool to allocate our command buffer from */
			VkCommandPoolCreateInfo cmd_pool_info = {
			queueFamilyIndex: queue_family_index,
			};

			auto res =
				vkCreateCommandPool(device, &cmd_pool_info, null, &cmd_pool);
			enforce(res == VK_SUCCESS, "vkCreateCommandPool");

			/* Create the command buffer from the command pool */
			VkCommandBufferAllocateInfo cmd_info = {
			commandPool: cmd_pool,
			level: VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
			commandBufferCount: 1,
			};

			res = vkAllocateCommandBuffers(device, &cmd_info, &cmd);
			enforce(res == VkResult.VK_SUCCESS, "vkAllocateCommandBuffers");

			info("04-init_command_buffer");
		}
		+/

		// 05-init_swapchain
		if(!createSwapchain(hinstance, hwnd)){
			return false;
		}

        return true;
    }

	void enforceVkResult(VkResult res, string msg)
	{
		if(res==VkResult.VK_SUCCESS){
			return;
		}

		foreach (member; EnumMembers!VkResult)
		{
			if(member==res){
				assert(false, to!string(member) ~ " " ~ msg);
			}
		}

		assert(false, msg);
	}

	struct VkWin32SurfaceCreateInfoKHR
	{
		VkStructureType sType = VkStructureType.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
		const(void)* pNext;
		VkFlags flags;
		HINSTANCE hinstance;
		HWND hwnd;
	};

	bool createSwapchain(HINSTANCE hinstance, HWND hwnd)
	{
		info("05-init_swapchain");

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
										   null, &surface);

		enforceVkResult(res, "vkCreateWin32SurfaceKHR");

		// Iterate over each queue to learn whether it supports presenting:
		auto pSupportsPresent = new VkBool32[queue_props.length];
		foreach(i, ref present; pSupportsPresent)
		{
			vkGetPhysicalDeviceSurfaceSupportKHR(gpus[0], i, surface,
												 &present);
		}

		// Search for a graphics and a present queue in the array of queue
		// families, try to find one that supports both
		auto graphics_queue_family_index = uint.max;
		auto present_queue_family_index = uint.max;
		foreach(i, ref prop; queue_props){
			if ((prop.queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
				if (graphics_queue_family_index == uint.max){
					graphics_queue_family_index = i;
				}

				if (pSupportsPresent[i] == VK_TRUE) {
					graphics_queue_family_index = i;
					present_queue_family_index = i;
					break;
				}
			}
		}

		if (present_queue_family_index == uint.max) {
			// If didn't find a queue that supports both graphics and present, then
			// find a separate present queue.
			foreach(i, present; pSupportsPresent)
			{
				if (present == VK_TRUE) {
					present_queue_family_index = i;
					break;
				}
			}
		}

		// Generate error if could not find queues that support graphics
		// and present
		if (graphics_queue_family_index == uint.max ||
			present_queue_family_index == uint.max) 
		{
			fatal("Could not find a queues for graphics and present");
		}

		if(!initDevice(graphics_queue_family_index)){
			error("fail to initDevice");
			return false;
		}

		// Get the list of VkFormats that are supported:
		uint formatCount;
		res = vkGetPhysicalDeviceSurfaceFormatsKHR(gpus[0], surface,
												   &formatCount, null);
		assert(res == VkResult.VK_SUCCESS);

		auto surfFormats = new VkSurfaceFormatKHR[formatCount];
		res = vkGetPhysicalDeviceSurfaceFormatsKHR(gpus[0], surface,
												   &formatCount, surfFormats.ptr);
		assert(res == VkResult.VK_SUCCESS);

		// If the format list includes just one entry of VK_FORMAT_UNDEFINED,
		// the surface has no preferred format.  Otherwise, at least one
		// supported format will be returned.
		VkFormat format;
		if (formatCount == 1 && surfFormats[0].format == VkFormat.VK_FORMAT_UNDEFINED) {
			format = VK_FORMAT_B8G8R8A8_UNORM;
		} 
		else {
			assert(formatCount >= 1);
			format = surfFormats[0].format;
		}

		VkSurfaceCapabilitiesKHR surfCapabilities;
		res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpus[0], surface,
														&surfCapabilities);
		assert(res == VkResult.VK_SUCCESS);

		uint presentModeCount;
		res = vkGetPhysicalDeviceSurfacePresentModesKHR(gpus[0], surface,
														&presentModeCount, null);
		assert(res == VkResult.VK_SUCCESS);

		auto presentModes = new VkPresentModeKHR[presentModeCount];
		res = vkGetPhysicalDeviceSurfacePresentModesKHR(
														gpus[0], surface, &presentModeCount, presentModes.ptr);
		assert(res == VK_SUCCESS);

		VkExtent2D swapchainExtent;
		auto width=50;
		auto height=50;
		// width and height are either both 0xFFFFFFFF, or both not 0xFFFFFFFF.
		if (surfCapabilities.currentExtent.width == 0xFFFFFFFF) {
			// If the surface size is undefined, the size is set to
			// the size of the images requested.
			swapchainExtent.width = width;
			swapchainExtent.height = height;
			if (swapchainExtent.width < surfCapabilities.minImageExtent.width) {
				swapchainExtent.width = surfCapabilities.minImageExtent.width;
			} else if (swapchainExtent.width >
					   surfCapabilities.maxImageExtent.width) {
						   swapchainExtent.width = surfCapabilities.maxImageExtent.width;
					   }

			if (swapchainExtent.height < surfCapabilities.minImageExtent.height) {
				swapchainExtent.height = surfCapabilities.minImageExtent.height;
			} else if (swapchainExtent.height >
					   surfCapabilities.maxImageExtent.height) {
						   swapchainExtent.height = surfCapabilities.maxImageExtent.height;
					   }
		} 
		else {
			// If the surface size is defined, the swap chain size must match
			swapchainExtent = surfCapabilities.currentExtent;
		}

		// If mailbox mode is available, use it, as is the lowest-latency non-
		// tearing mode.  If not, try IMMEDIATE which will usually be available,
		// and is fastest (though it tears).  If not, fall back to FIFO which is
		// always available.
		VkPresentModeKHR swapchainPresentMode = VK_PRESENT_MODE_FIFO_KHR;
		foreach(mode; presentModes){

			if (mode == VK_PRESENT_MODE_MAILBOX_KHR) {
				swapchainPresentMode = VK_PRESENT_MODE_MAILBOX_KHR;
				break;
			}
			if ((swapchainPresentMode != VK_PRESENT_MODE_MAILBOX_KHR) &&
				(mode == VK_PRESENT_MODE_IMMEDIATE_KHR)) {
					swapchainPresentMode = VK_PRESENT_MODE_IMMEDIATE_KHR;
				}
		}

		// Determine the number of VkImage's to use in the swap chain.
		// We need to acquire only 1 presentable image at at time.
		// Asking for minImageCount images ensures that we can acquire
		// 1 presentable image as long as we present it before attempting
		// to acquire another.
		uint desiredNumberOfSwapChainImages = surfCapabilities.minImageCount;
		VkSurfaceTransformFlagBitsKHR preTransform;
		if (surfCapabilities.supportedTransforms &
			VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR) 
		{
			preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
		} 
		else {
			preTransform = surfCapabilities.currentTransform;
		}

		VkSwapchainCreateInfoKHR swapchain_ci = {
			sType : VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
			//pNext : NULL,
			surface : surface,
			minImageCount : desiredNumberOfSwapChainImages,
			imageFormat : format,
			imageExtent: {
				width : swapchainExtent.width,
				height : swapchainExtent.height,
			},
			preTransform : preTransform,
			compositeAlpha : VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
			imageArrayLayers : 1,
			presentMode : swapchainPresentMode,
			//oldSwapchain : VK_NULL_HANDLE,
			clipped : true,
			imageColorSpace : VK_COLORSPACE_SRGB_NONLINEAR_KHR,
			imageUsage : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
			imageSharingMode : VK_SHARING_MODE_EXCLUSIVE,
			queueFamilyIndexCount : 0,
			pQueueFamilyIndices : NULL,
		};

		auto queueFamilyIndices = [graphics_queue_family_index, present_queue_family_index];
		if (graphics_queue_family_index != present_queue_family_index) {
			// If the graphics and present queues are from different queue families,
			// we either have to explicitly transfer ownership of images between
			// the queues, or we have to create the swapchain with imageSharingMode
			// as VK_SHARING_MODE_CONCURRENT
			swapchain_ci.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
			swapchain_ci.queueFamilyIndexCount = 2;
			swapchain_ci.pQueueFamilyIndices = queueFamilyIndices.ptr;
		}

		res = vkCreateSwapchainKHR(device, &swapchain_ci, null,
									&swap_chain);
		assert(res == VK_SUCCESS);

		uint swapchainImageCount;
		res = vkGetSwapchainImagesKHR(device, swap_chain,
									  &swapchainImageCount, null);
		assert(res == VK_SUCCESS);

		auto swapchainImages = new VkImage[swapchainImageCount];
		res = vkGetSwapchainImagesKHR(device, swap_chain,
									  &swapchainImageCount, swapchainImages.ptr);
		assert(res == VK_SUCCESS);

		buffers=swapchainImages.map!((a){
			swap_chain_buffer buffer={
				image: a,
			};
			return buffer;
		}).array;

		/+
		for (uint32_t i = 0; i < info.swapchainImageCount; i++) {
		VkImageViewCreateInfo color_image_view = {};
		color_image_view.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
		color_image_view.pNext = NULL;
		color_image_view.flags = 0;
		color_image_view.image = info.buffers[i].image;
		color_image_view.viewType = VK_IMAGE_VIEW_TYPE_2D;
		color_image_view.format = info.format;
		color_image_view.components.r = VK_COMPONENT_SWIZZLE_R;
		color_image_view.components.g = VK_COMPONENT_SWIZZLE_G;
		color_image_view.components.b = VK_COMPONENT_SWIZZLE_B;
		color_image_view.components.a = VK_COMPONENT_SWIZZLE_A;
		color_image_view.subresourceRange.aspectMask =
		VK_IMAGE_ASPECT_COLOR_BIT;
		color_image_view.subresourceRange.baseMipLevel = 0;
		color_image_view.subresourceRange.levelCount = 1;
		color_image_view.subresourceRange.baseArrayLayer = 0;
		color_image_view.subresourceRange.layerCount = 1;

		res = vkCreateImageView(info.device, &color_image_view, NULL,
		&info.buffers[i].view);
		assert(res == VK_SUCCESS);

		+/
		return true;
	}

	bool initDevice(uint graphics_queue_family_index)
	{
		VkDeviceQueueCreateInfo queue_info = {
			queueCount: 1,
			pQueuePriorities: [0.0f].ptr,
			queueFamilyIndex: graphics_queue_family_index,
		};

		auto device_extension_names=[ to!string(VK_KHR_SWAPCHAIN_EXTENSION_NAME) ];
		VkDeviceCreateInfo device_info = {
			queueCreateInfoCount : 1,
			pQueueCreateInfos : &queue_info,
			enabledExtensionCount : device_extension_names.length,
			ppEnabledExtensionNames : device_extension_names.map!("a.ptr").array.ptr,
		};

		auto res = vkCreateDevice(gpus[0], &device_info, NULL, &device);

		return res==VkResult.VK_SUCCESS;
	}
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

    VulkanManager vulkan;
    if(!vulkan.initialize(GetModuleHandle(null), glfw.get_hwnd())){
        return;
    }
    log("vulkan.initialized");

	while(glfw.newFrame()){
		//
	}
}

