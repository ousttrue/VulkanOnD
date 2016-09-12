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


struct VulkanManager
{
    VkInstance inst;
    VkPhysicalDevice[] gpus;
	VkQueueFamilyProperties[] queue_props;

    VkDevice device;
    VkQueue graphics_queue;
    VkQueue present_queue;
	uint graphics_queue_family_index;
	uint present_queue_family_index;

	VkCommandPool cmd_pool;
	VkCommandBuffer cmd;

	VkFormat format;
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

	VkDescriptorPool desc_pool;
	VkDescriptorSet[] desc_set;

    uint current_buffer;
    VkRenderPass render_pass;
	VkSemaphore imageAcquiredSemaphore;

    VkPipelineShaderStageCreateInfo[2] shaderStages;

	static this()
	{
		log("DVulkanDerelict.load.");
		DVulkanDerelict.load();
		DVulkanDerelict.loadInitializationFunctions();
	}

    ~this()
    {
		log("~VulkanManager");

		vkDestroyShaderModule(device, shaderStages[0]._module, NULL);
		vkDestroyShaderModule(device, shaderStages[1]._module, NULL);

		vkDestroyRenderPass(device, render_pass, NULL);
		vkDestroySemaphore(device, imageAcquiredSemaphore, NULL);

		vkDestroyDescriptorPool(device, desc_pool, NULL);

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

			graphics_queue_family_index = -1;
			for(int i=0; i<queue_props.length; ++i)
			{
				if(queue_props[i].queueFlags & VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT){
					graphics_queue_family_index=i;
					break;
				}
			}
			enforce(graphics_queue_family_index>= 0);

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

		int width=50;
		int height=50;

		// 05-init_swapchain
		if(!createSwapchain(hinstance, hwnd
							, width, height)){
			error("fail to createSwapchain");
			return false;
		}

		init_command_pool();
		init_command_buffer();
		execute_begin_command_buffer();
		init_device_queue();

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

		// 09-init_descriptor_set
		{
			auto type_count=new VkDescriptorPoolSize[1];
			type_count[0].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
			type_count[0].descriptorCount = 1;

			VkDescriptorPoolCreateInfo descriptor_pool = {};
			descriptor_pool.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
			descriptor_pool.pNext = NULL;
			descriptor_pool.maxSets = 1;
			descriptor_pool.poolSizeCount = type_count.length;
			descriptor_pool.pPoolSizes = type_count.ptr;

			auto res = vkCreateDescriptorPool(device, &descriptor_pool, NULL,
										 &desc_pool);
			assert(res == VK_SUCCESS);

			auto alloc_info=new VkDescriptorSetAllocateInfo[1];
			alloc_info[0].sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
			alloc_info[0].pNext = NULL;
			alloc_info[0].descriptorPool = desc_pool;
			alloc_info[0].descriptorSetCount = desc_layout.length;
			alloc_info[0].pSetLayouts = desc_layout.ptr;

			desc_set=new VkDescriptorSet[desc_layout.length];
			res =
				vkAllocateDescriptorSets(device, alloc_info.ptr, desc_set.ptr);
			assert(res == VK_SUCCESS);

			auto writes=new VkWriteDescriptorSet[1];

			writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
			writes[0].pNext = NULL;
			writes[0].dstSet = desc_set[0];
			writes[0].descriptorCount = 1;
			writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
			writes[0].pBufferInfo = &uniform_data.buffer_info;
			writes[0].dstArrayElement = 0;
			writes[0].dstBinding = 0;

			vkUpdateDescriptorSets(device, 1, writes.ptr, 0, NULL);
		}
		info("09-init_descriptor_set");

		// 10-init_render_pass
		{
			// A semaphore (or fence) is required in order to acquire a
			// swapchain image to prepare it for use in a render pass.
			// The semaphore is normally used to hold back the rendering
			// operation until the image is actually available.
			// But since this sample does not render, the semaphore
			// ends up being unused.
			VkSemaphoreCreateInfo imageAcquiredSemaphoreCreateInfo;
			imageAcquiredSemaphoreCreateInfo.sType =
				VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
			imageAcquiredSemaphoreCreateInfo.pNext = NULL;
			imageAcquiredSemaphoreCreateInfo.flags = 0;

			auto res = vkCreateSemaphore(device, &imageAcquiredSemaphoreCreateInfo,
									NULL, &imageAcquiredSemaphore);
			assert(res == VK_SUCCESS);

			// Acquire the swapchain image in order to set its layout
			res = vkAcquireNextImageKHR(device, swap_chain, ulong.max,
										imageAcquiredSemaphore, 0,
										&current_buffer);
			assert(res >= 0);

			// Set the layout for the color buffer, transitioning it from
			// undefined to an optimal color attachment to make it usable in
			// a render pass.
			// The depth buffer layout has already been set by init_depth_buffer().
			set_image_layout(buffers[current_buffer].image,
							 VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_UNDEFINED,
							 VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);

			// Stop recording the command buffer here since this sample will not
			// actually put the render pass in the command buffer (via vkCmdBeginRenderPass).
			// An actual application might leave the command buffer in recording mode
			// and insert a BeginRenderPass command after the image layout transition
			// memory barrier commands.
			// This sample simply creates and defines the render pass.
			//execute_end_command_buffer(info);
			res = vkEndCommandBuffer(cmd);
			assert(res == VK_SUCCESS);

			/* Need attachments for render target and depth buffer */
			auto attachments=new VkAttachmentDescription[2];
			attachments[0].format = format;
			attachments[0].samples = NUM_SAMPLES;
			attachments[0].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
			attachments[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
			attachments[0].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
			attachments[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
			attachments[0].initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
			attachments[0].finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
			attachments[0].flags = 0;

			attachments[1].format = depth.format;
			attachments[1].samples = NUM_SAMPLES;
			attachments[1].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
			attachments[1].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
			attachments[1].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
			attachments[1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
			attachments[1].initialLayout =
				VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
			attachments[1].finalLayout =
				VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
			attachments[1].flags = 0;

			VkAttachmentReference color_reference = {};
			color_reference.attachment = 0;
			color_reference.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

			VkAttachmentReference depth_reference = {};
			depth_reference.attachment = 1;
			depth_reference.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

			VkSubpassDescription subpass = {};
			subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
			subpass.flags = 0;
			subpass.inputAttachmentCount = 0;
			subpass.pInputAttachments = NULL;
			subpass.colorAttachmentCount = 1;
			subpass.pColorAttachments = &color_reference;
			subpass.pResolveAttachments = NULL;
			subpass.pDepthStencilAttachment = &depth_reference;
			subpass.preserveAttachmentCount = 0;
			subpass.pPreserveAttachments = NULL;

			VkRenderPassCreateInfo rp_info = {};
			rp_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
			rp_info.pNext = NULL;
			rp_info.attachmentCount = 2;
			rp_info.pAttachments = attachments.ptr;
			rp_info.subpassCount = 1;
			rp_info.pSubpasses = &subpass;
			rp_info.dependencyCount = 0;
			rp_info.pDependencies = NULL;

			res = vkCreateRenderPass(device, &rp_info, NULL, &render_pass);
			assert(res == VK_SUCCESS);

		}
		info("10-init_render_pass");

		// 11-init_shaders
		if(!init_shaders("cube-vert.spv", "cube-frag.spv")){
			return false;
		}
		info("11-init_shaders");

        return true;
    }

	bool init_shaders(string vertSpv, string fragSpv)
	{
		/* VULKAN_KEY_START */
		{
			auto vtx_spv=read(vertSpv);
			VkShaderModuleCreateInfo moduleCreateInfo;
			moduleCreateInfo.codeSize = vtx_spv.length;
			moduleCreateInfo.pCode = cast(uint*)vtx_spv.ptr;
			auto res = vkCreateShaderModule(device, &moduleCreateInfo, NULL,
									   &shaderStages[0]._module);
			assert(res == VK_SUCCESS);
		}

		{
			auto frag_spv=read(fragSpv);
			VkShaderModuleCreateInfo moduleCreateInfo;
			moduleCreateInfo.codeSize = frag_spv.length;
			moduleCreateInfo.pCode = cast(uint*)frag_spv.ptr;
			auto res = vkCreateShaderModule(device, &moduleCreateInfo, NULL,
									   &shaderStages[1]._module);
			assert(res == VK_SUCCESS);
		}

		return true;
	}

	void init_command_pool() {
		/* DEPENDS on init_swapchain_extension() */
		VkCommandPoolCreateInfo cmd_pool_info = {};
		cmd_pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
		cmd_pool_info.pNext = NULL;
		cmd_pool_info.queueFamilyIndex = graphics_queue_family_index;
		cmd_pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;

		auto res =
			vkCreateCommandPool(device, &cmd_pool_info, NULL, &cmd_pool);
		assert(res == VK_SUCCESS);
	}

	void init_command_buffer() {
		/* DEPENDS on init_swapchain_extension() and init_command_pool() */
		VkCommandBufferAllocateInfo cmd_info = {};
		cmd_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
		cmd_info.pNext = NULL;
		cmd_info.commandPool = cmd_pool;
		cmd_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
		cmd_info.commandBufferCount = 1;

		auto res = vkAllocateCommandBuffers(device, &cmd_info, &cmd);
		assert(res == VK_SUCCESS);
	}

	void execute_begin_command_buffer() {
		/* DEPENDS on init_command_buffer() */

		VkCommandBufferBeginInfo cmd_buf_info = {};
		cmd_buf_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
		cmd_buf_info.pNext = NULL;
		cmd_buf_info.flags = 0;
		cmd_buf_info.pInheritanceInfo = NULL;

		auto res = vkBeginCommandBuffer(cmd, &cmd_buf_info);
		assert(res == VK_SUCCESS);
	}

	void init_device_queue() {
		/* DEPENDS on init_swapchain_extension() */

		vkGetDeviceQueue(device, graphics_queue_family_index, 0,
						 &graphics_queue);
		if (graphics_queue_family_index == present_queue_family_index) {
			present_queue = graphics_queue;
		} else {
			vkGetDeviceQueue(device, present_queue_family_index, 0,
							 &present_queue);
		}
	}

	void set_image_layout(VkImage image,
						  VkImageAspectFlags aspectMask,
						  VkImageLayout old_image_layout,
						  VkImageLayout new_image_layout) {
							  /* DEPENDS on cmd and queue initialized */

							  assert(cmd != VkCommandBuffer.init);
							  assert(graphics_queue != VkQueue.init);

							  VkImageMemoryBarrier image_memory_barrier = {};
							  image_memory_barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
							  image_memory_barrier.pNext = NULL;
							  image_memory_barrier.srcAccessMask = 0;
							  image_memory_barrier.dstAccessMask = 0;
							  image_memory_barrier.oldLayout = old_image_layout;
							  image_memory_barrier.newLayout = new_image_layout;
							  image_memory_barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
							  image_memory_barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
							  image_memory_barrier.image = image;
							  image_memory_barrier.subresourceRange.aspectMask = aspectMask;
							  image_memory_barrier.subresourceRange.baseMipLevel = 0;
							  image_memory_barrier.subresourceRange.levelCount = 1;
							  image_memory_barrier.subresourceRange.baseArrayLayer = 0;
							  image_memory_barrier.subresourceRange.layerCount = 1;

							  if (old_image_layout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
								  image_memory_barrier.srcAccessMask =
									  VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
							  }

							  if (new_image_layout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
								  image_memory_barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
							  }

							  if (new_image_layout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL) {
								  image_memory_barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
							  }

							  if (old_image_layout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
								  image_memory_barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
							  }

							  if (old_image_layout == VK_IMAGE_LAYOUT_PREINITIALIZED) {
								  image_memory_barrier.srcAccessMask = VK_ACCESS_HOST_WRITE_BIT;
							  }

							  if (new_image_layout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
								  image_memory_barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
							  }

							  if (new_image_layout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
								  image_memory_barrier.dstAccessMask =
									  VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
							  }

							  if (new_image_layout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
								  image_memory_barrier.dstAccessMask =
									  VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
							  }

							  VkPipelineStageFlags src_stages = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
							  VkPipelineStageFlags dest_stages = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;

							  vkCmdPipelineBarrier(cmd, src_stages, dest_stages, 0, 0, NULL, 0, NULL,
												   1, &image_memory_barrier);
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
		graphics_queue_family_index = uint.max;
		present_queue_family_index = uint.max;
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


		//depth.format = depth_format;

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

