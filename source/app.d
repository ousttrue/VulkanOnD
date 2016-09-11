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
import core.stdc.string;
import gfm.math;


immutable NUM_DESCRIPTOR_SETS=1;


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

	struct depth_buffer
	{
        VkFormat format;

        VkImage image;
        VkDeviceMemory mem;
        VkImageView view;
    };
	depth_buffer depth;

	mat4x4!float MVP;
    struct uniform_buffer {
        VkBuffer buf;
        VkDeviceMemory mem;
        VkDescriptorBufferInfo buffer_info;
    };
	uniform_buffer uniform_data;

	VkDescriptorSetLayout[] desc_layout;
	VkPipelineLayout pipeline_layout;

	static this()
	{
		log("DVulkanDerelict.load.");
		DVulkanDerelict.load();
		DVulkanDerelict.loadInitializationFunctions();
	}

    ~this()
    {
		log("~VulkanManager");

		for (int i = 0; i < NUM_DESCRIPTOR_SETS; i++)
			vkDestroyDescriptorSetLayout(device, desc_layout[i], NULL);
		vkDestroyPipelineLayout(device, pipeline_layout, NULL);

		vkDestroyBuffer(device, uniform_data.buf, NULL);
		vkFreeMemory(device, uniform_data.mem, NULL);

		vkDestroyImageView(device, depth.view, null);
		vkDestroyImage(device, depth.image, null);
		vkFreeMemory(device, depth.mem, null);

		for (uint i = 0; i < buffers.length; i++) {
			vkDestroyImageView(device, buffers[i].view, null);
		}
		vkDestroySwapchainKHR(device, swap_chain, null);
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

		int width=50;
		int height=50;

		// 05-init_swapchain
		if(!createSwapchain(hinstance, hwnd
							, width, height)){
			error("fail to createSwapchain");
			return false;
		}

		// 06-init_depth_buffer
		if(!createDepthBuffer(width, height)){
			error("fail to createDepthBuffer");
			return false;
		}

		// 07-init_uniform_buffer
		if(!createUniformBuffer()){
			error("fali to createUniformBuffer");
			return false;
		}
		info("07-init_uniform_buffer");

		// 08-init_pipeline_layout
		if(!createPipelineLayout())
		{
			error("fail to createPipelineLayout");
			return false;
		}
		info("08-init_pipeline_layout");

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

	bool createSwapchain(HINSTANCE hinstance, HWND hwnd
						 , int width, int height)
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

		for (uint i = 0; i < swapchainImageCount; i++) {
			VkImageViewCreateInfo color_image_view = {
				image : buffers[i].image,
				viewType : VK_IMAGE_VIEW_TYPE_2D,
				format : format,
				components: {
					r : VK_COMPONENT_SWIZZLE_R,
					g : VK_COMPONENT_SWIZZLE_G,
					b : VK_COMPONENT_SWIZZLE_B,
					a : VK_COMPONENT_SWIZZLE_A,
				},
				subresourceRange:{
					aspectMask :VK_IMAGE_ASPECT_COLOR_BIT,
					baseMipLevel : 0,
					levelCount : 1,
					baseArrayLayer : 0,
					layerCount : 1,
				},
			};

			res = vkCreateImageView(device, &color_image_view, null,
									&buffers[i].view);
			assert(res == VK_SUCCESS);
		}

		info("05-init_swapchain");
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

	bool createDepthBuffer(int width, int height)
	{
		const VkFormat depth_format = VK_FORMAT_D16_UNORM;
		VkFormatProperties props;
		vkGetPhysicalDeviceFormatProperties(gpus[0], depth_format, &props);

		VkImageCreateInfo image_info;
		if (props.linearTilingFeatures &
			VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
				image_info.tiling = VK_IMAGE_TILING_LINEAR;
		} 
		else if (props.optimalTilingFeatures &
				 VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) 
		{
			image_info.tiling = VK_IMAGE_TILING_OPTIMAL;
		} 
		else 
		{
			/* Try other depth formats? */
			fatal("VK_FORMAT_D16_UNORM Unsupported.");
		}

		image_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
		image_info.pNext = NULL;
		image_info.imageType = VK_IMAGE_TYPE_2D;
		image_info.format = depth_format;
		image_info.extent.width = width;
		image_info.extent.height = height;
		image_info.extent.depth = 1;
		image_info.mipLevels = 1;
		image_info.arrayLayers = 1;
		image_info.samples = VK_SAMPLE_COUNT_1_BIT;
		image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		image_info.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
		image_info.queueFamilyIndexCount = 0;
		image_info.pQueueFamilyIndices = NULL;
		image_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
		image_info.flags = 0;

		VkMemoryAllocateInfo mem_alloc;
		mem_alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
		mem_alloc.pNext = NULL;
		mem_alloc.allocationSize = 0;
		mem_alloc.memoryTypeIndex = 0;

		VkImageViewCreateInfo view_info;
		view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
		view_info.pNext = NULL;
		//view_info.image = VK_NULL_HANDLE;
		view_info.format = depth_format;
		view_info.components.r = VK_COMPONENT_SWIZZLE_R;
		view_info.components.g = VK_COMPONENT_SWIZZLE_G;
		view_info.components.b = VK_COMPONENT_SWIZZLE_B;
		view_info.components.a = VK_COMPONENT_SWIZZLE_A;
		view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
		view_info.subresourceRange.baseMipLevel = 0;
		view_info.subresourceRange.levelCount = 1;
		view_info.subresourceRange.baseArrayLayer = 0;
		view_info.subresourceRange.layerCount = 1;
		view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
		view_info.flags = 0;


		//info.depth.format = depth_format;

		/* Create image */
		auto res = vkCreateImage(device, &image_info, null, &depth.image);
		assert(res == VK_SUCCESS);

		VkMemoryRequirements mem_reqs;
		vkGetImageMemoryRequirements(device, depth.image, &mem_reqs);

		mem_alloc.allocationSize = mem_reqs.size;
		/* Use the memory properties to determine the type of memory required */
		auto pass = memory_type_from_properties(mem_reqs.memoryTypeBits,
										   0, /* No Requirements */
										   &mem_alloc.memoryTypeIndex);
		assert(pass);

		/* Allocate memory */
		res = vkAllocateMemory(device, &mem_alloc, null, &depth.mem);
		assert(res == VK_SUCCESS);

		/* Bind memory */
		res = vkBindImageMemory(device, depth.image, depth.mem, 0);
		assert(res == VK_SUCCESS);

		/* Create image view */
		view_info.image = depth.image;
		res = vkCreateImageView(device, &view_info, null, &depth.view);
		assert(res == VK_SUCCESS);

		info("06-init_depth_buffer");
		return true;
	}

	bool memory_type_from_properties(uint typeBits,
									 VkFlags requirements_mask,
									 uint32_t *typeIndex) 
	{
		VkPhysicalDeviceMemoryProperties memory_properties;
		vkGetPhysicalDeviceMemoryProperties(gpus[0], &memory_properties);
		// Search memtypes to find first index with those properties
		for (uint i = 0; i < memory_properties.memoryTypeCount; i++) {
			if ((typeBits & 1) == 1) {
				// Type is available, does it match user properties?
				if ((memory_properties.memoryTypes[i].propertyFlags &
					 requirements_mask) == requirements_mask) {
						 *typeIndex = i;
						 return true;
					 }
			}
			typeBits >>= 1;
		}
		// No memory types matched, return failure
		return false;
	}

	bool createUniformBuffer()
	{
		VkBufferCreateInfo buf_info;
		buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
		buf_info.pNext = NULL;
		buf_info.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
		buf_info.size = MVP.sizeof;
		buf_info.queueFamilyIndexCount = 0;
		buf_info.pQueueFamilyIndices = NULL;
		buf_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
		buf_info.flags = 0;
		auto res = vkCreateBuffer(device, &buf_info, null, &uniform_data.buf);
		assert(res == VK_SUCCESS);

		VkMemoryRequirements mem_reqs;
		vkGetBufferMemoryRequirements(device, uniform_data.buf,
									  &mem_reqs);

		VkMemoryAllocateInfo alloc_info = {};
		alloc_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
		alloc_info.pNext = NULL;
		alloc_info.memoryTypeIndex = 0;

		alloc_info.allocationSize = mem_reqs.size;
		auto pass = memory_type_from_properties(mem_reqs.memoryTypeBits,
										   VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                           VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
										   &alloc_info.memoryTypeIndex);
		assert(pass && "No mappable, coherent memory");

		res = vkAllocateMemory(device, &alloc_info, NULL,
							   &(uniform_data.mem));
		assert(res == VK_SUCCESS);

		uint *pData;
		res = vkMapMemory(device, uniform_data.mem, 0, mem_reqs.size, 0,
						  cast(void**)&pData);
		assert(res == VK_SUCCESS);

		memcpy(pData, MVP.ptr, MVP.sizeof);

		vkUnmapMemory(device, uniform_data.mem);

		res = vkBindBufferMemory(device, uniform_data.buf,
								 uniform_data.mem, 0);
		assert(res == VK_SUCCESS);

		uniform_data.buffer_info.buffer = uniform_data.buf;
		uniform_data.buffer_info.offset = 0;
		uniform_data.buffer_info.range = MVP.sizeof;

		return true;
	}

	bool createPipelineLayout()
	{
		/* Start with just our uniform buffer that has our transformation matrices
		* (for the vertex shader). The fragment shader we intend to use needs no
		* external resources, so nothing else is necessary
		*/

		/* Note that when we start using textures, this is where our sampler will
		* need to be specified
		*/
		VkDescriptorSetLayoutBinding layout_binding = {};
		layout_binding.binding = 0;
		layout_binding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		layout_binding.descriptorCount = 1;
		layout_binding.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
		layout_binding.pImmutableSamplers = NULL;

		/* Next take layout bindings and use them to create a descriptor set layout
		*/
		VkDescriptorSetLayoutCreateInfo descriptor_layout = {};
		descriptor_layout.sType =
			VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
		descriptor_layout.pNext = NULL;
		descriptor_layout.bindingCount = 1;
		descriptor_layout.pBindings = &layout_binding;

		desc_layout=new VkDescriptorSetLayout[NUM_DESCRIPTOR_SETS];
		auto res = vkCreateDescriptorSetLayout(device, &descriptor_layout, NULL,
										  desc_layout.ptr);
		assert(res == VK_SUCCESS);

		/* Now use the descriptor layout to create a pipeline layout */
		VkPipelineLayoutCreateInfo pPipelineLayoutCreateInfo = {};
		pPipelineLayoutCreateInfo.sType =
			VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
		pPipelineLayoutCreateInfo.pNext = NULL;
		pPipelineLayoutCreateInfo.pushConstantRangeCount = 0;
		pPipelineLayoutCreateInfo.pPushConstantRanges = NULL;
		pPipelineLayoutCreateInfo.setLayoutCount = NUM_DESCRIPTOR_SETS;
		pPipelineLayoutCreateInfo.pSetLayouts = desc_layout.ptr;

		res = vkCreatePipelineLayout(device, &pPipelineLayoutCreateInfo, NULL,
									 &pipeline_layout);
		assert(res == VK_SUCCESS);

		return true;
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

