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

enum VK_KHR_WIN32_SURFACE_EXTENSION_NAME = "VK_KHR_win32_surface";

/* Number of viewports and number of scissors have to be the same */
/* at pipeline creation and in any call to set them dynamically   */
/* They also have to be the same as each other                    */
immutable NUM_VIEWPORTS =1;
immutable NUM_SCISSORS=NUM_VIEWPORTS;

bool memory_type_from_properties(ref sample_info info, uint typeBits,
                                 VkFlags requirements_mask,
                                 uint *typeIndex) 
{
	// Search memtypes to find first index with those properties
	for (uint32_t i = 0; i < info.memory_properties.memoryTypeCount; i++) {
		if ((typeBits & 1) == 1) {
			// Type is available, does it match user properties?
			if ((info.memory_properties.memoryTypes[i].propertyFlags &
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

void set_image_layout(ref sample_info info, VkImage image,
                      VkImageAspectFlags aspectMask,
                      VkImageLayout old_image_layout,
                      VkImageLayout new_image_layout) 
{
	/* DEPENDS on info.cmd and info.queue initialized */

	assert(info.cmd != VkCommandBuffer.init);
	assert(info.graphics_queue != VkQueue.init);

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

	vkCmdPipelineBarrier(info.cmd, src_stages, dest_stages, 0, 0, NULL, 0, NULL,
						 1, &image_memory_barrier);
}


/*
* structure to track all objects related to a texture.
*/
struct texture_object 
{
    VkSampler sampler;

    VkImage image;
    VkImageLayout imageLayout;

    VkDeviceMemory mem;
    VkImageView view;
    int32_t tex_width, tex_height;
};

/*
* Keep each of our swap chain buffers' image, command buffer and view in one
* spot
*/
struct swap_chain_buffer
{
    VkImage image;
    VkImageView view;
};

/*
* A layer can expose extensions, keep track of those
* extensions here.
*/
struct layer_properties
{
    VkLayerProperties properties;
	VkExtensionProperties[] extensions;
};

/*
* Structure for tracking information used / created / modified
* by utility functions.
*/
struct sample_info 
{
	version(Windows){
    HINSTANCE connection;        // hInstance - Windows Instance
    string name; // Name to put on the window/icon
    HWND window;                 // hWnd - window handle
	}
    VkSurfaceKHR surface;
    bool prepared;
    bool use_staging_buffer;
    bool save_images;

	string[] instance_layer_names;
	string[] instance_extension_names;
	layer_properties[] instance_layer_properties;
	VkExtensionProperties[] instance_extension_properties;
    VkInstance inst;

	string[] device_extension_names;
	VkExtensionProperties[] device_extension_properties;
	VkPhysicalDevice[] gpus;
    VkDevice device;
    VkQueue graphics_queue;
    VkQueue present_queue;
    uint graphics_queue_family_index;
    uint present_queue_family_index;
    VkPhysicalDeviceProperties gpu_props;
	VkQueueFamilyProperties[] queue_props;
    VkPhysicalDeviceMemoryProperties memory_properties;

    VkFramebuffer[] framebuffers;
    int width, height;
    VkFormat format;

    uint swapchainImageCount;
    VkSwapchainKHR swap_chain;
	swap_chain_buffer[] buffers;
    VkSemaphore imageAcquiredSemaphore;

    VkCommandPool cmd_pool;

    struct depth_t {
        VkFormat format;

        VkImage image;
        VkDeviceMemory mem;
        VkImageView view;
    }
	depth_t depth;

	texture_object[] textures;

    struct uniform_t {
        VkBuffer buf;
        VkDeviceMemory mem;
        VkDescriptorBufferInfo buffer_info;
    }
	uniform_t uniform_data;

    struct texture_t{
        VkDescriptorImageInfo image_info;
    } 
	texture_t texture_data;
    VkDeviceMemory stagingMemory;
    VkImage stagingImage;

    struct vertex_t {
        VkBuffer buf;
        VkDeviceMemory mem;
        VkDescriptorBufferInfo buffer_info;
    }
	vertex_t vertex_buffer;
    VkVertexInputBindingDescription vi_binding;
    VkVertexInputAttributeDescription[2] vi_attribs;

	mat4!float Projection;
	mat4!float View;
	mat4!float Model;
	mat4!float Clip;
	mat4!float MVP;

    VkCommandBuffer cmd; // Buffer for initialization commands
    VkPipelineLayout pipeline_layout;
	VkDescriptorSetLayout[] desc_layout;
    VkPipelineCache pipelineCache;
    VkRenderPass render_pass;
    VkPipeline pipeline;

    VkPipelineShaderStageCreateInfo[2] shaderStages;

    VkDescriptorPool desc_pool;
	VkDescriptorSet[] desc_set;

	/*
    PFN_vkCreateDebugReportCallbackEXT dbgCreateDebugReportCallback;
    PFN_vkDestroyDebugReportCallbackEXT dbgDestroyDebugReportCallback;
    PFN_vkDebugReportMessageEXT dbgBreakCallback;
	VkDebugReportCallbackEXT[] debug_report_callbacks;
	*/

    uint current_buffer;
    uint queue_family_count;

    VkViewport viewport;
    VkRect2D scissor;
};


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

/*
* TODO: function description here
*/
VkResult init_global_extension_properties(ref layer_properties layer_props) 
{
    VkExtensionProperties *instance_extensions;
    uint instance_extension_count;
    VkResult res;


    auto layer_name = layer_props.properties.layerName;

    do {
        res = vkEnumerateInstanceExtensionProperties(
													 layer_name.ptr, &instance_extension_count, NULL);
        if (res)
            return res;

        if (instance_extension_count == 0) {
            return VK_SUCCESS;
        }

        layer_props.extensions.length=instance_extension_count;
        instance_extensions = layer_props.extensions.ptr;
        res = vkEnumerateInstanceExtensionProperties(
													 layer_name.ptr, &instance_extension_count, instance_extensions);
    } while (res == VK_INCOMPLETE);

    return res;
}

/*
* TODO: function description here
*/
VkResult init_global_layer_properties(ref sample_info info) {
    uint instance_layer_count;
    VkLayerProperties[] vk_props;
    VkResult res;

    /*
	* It's possible, though very rare, that the number of
	* instance layers could change. For example, installing something
	* could include new layers that the loader would pick up
	* between the initial query for the count and the
	* request for VkLayerProperties. The loader indicates that
	* by returning a VK_INCOMPLETE status and will update the
	* the count parameter.
	* The count parameter will be updated with the number of
	* entries loaded into the data pointer - in case the number
	* of layers went down or is smaller than the size given.
	*/
    do {
        res = vkEnumerateInstanceLayerProperties(&instance_layer_count, NULL);
        if (res)
            return res;

        if (instance_layer_count == 0) {
            return VK_SUCCESS;
        }

        vk_props.length = instance_layer_count;

        res =
            vkEnumerateInstanceLayerProperties(&instance_layer_count, vk_props.ptr);
    } while (res == VK_INCOMPLETE);

    /*
	* Now gather the extension list for each instance layer.
	*/
    for (uint i = 0; i < instance_layer_count; i++) {
        layer_properties layer_props;
        layer_props.properties = vk_props[i];
        res = init_global_extension_properties(layer_props);
        if (res)
            return res;
        info.instance_layer_properties~=layer_props;
    }

    return res;
}

VkResult init_device_extension_properties(ref sample_info info,
                                          ref layer_properties layer_props) 
{
	/+
	VkExtensionProperties *device_extensions;
	uint device_extension_count;
	VkResult res;

	auto layer_name = layer_props.properties.layerName;

	do {
		res = vkEnumerateDeviceExtensionProperties(
												   info.gpus[0], layer_name.ptr, &device_extension_count, NULL);
		if (res)
			return res;

		if (device_extension_count == 0) {
			return VK_SUCCESS;
		}

		layer_props.extensions.length=device_extension_count;
		device_extensions = layer_props.extensions.ptr;
		res = vkEnumerateDeviceExtensionProperties(info.gpus[0], layer_name.ptr,
												   &device_extension_count,
												   device_extensions.ptr);
	} while (res == VK_INCOMPLETE);

	return res;
	+/
	return VK_SUCCESS;
}

/*
* Return 1 (true) if all layer names specified in check_names
* can be found in given layer properties.
*/
VkBool32 demo_check_layers(const layer_properties[] layer_props,
                           const string[] layer_names) 
{
	uint check_count = layer_names.length;
	uint layer_count = layer_props.length;
	for (uint i = 0; i < check_count; i++) {
		VkBool32 found = 0;
		for (uint j = 0; j < layer_count; j++) {
			if (layer_names[i]==layer_props[j].properties.layerName) {
				found = 1;
			}
		}
		if (!found) {
			log( "Cannot find layer: ", layer_names[i]);
			return 0;
		}
	}
	return 1;
}

void init_instance_extension_names(ref sample_info info) 
{
    info.instance_extension_names~=VK_KHR_SURFACE_EXTENSION_NAME;
	version(Windows){
		info.instance_extension_names~=VK_KHR_WIN32_SURFACE_EXTENSION_NAME;
	}
}

VkResult init_instance(ref sample_info info,
                       string app_short_name) 
{
	VkApplicationInfo app_info;
	app_info.pApplicationName = app_short_name.ptr;
	app_info.applicationVersion = 1;
	app_info.pEngineName = app_short_name.ptr;
	app_info.engineVersion = 1;
	app_info.apiVersion =  VK_MAKE_VERSION(1, 0, 0);

	VkInstanceCreateInfo inst_info;
	inst_info.pApplicationInfo = &app_info;
	inst_info.enabledLayerCount = info.instance_layer_names.length;
	auto instance_layer_names=info.instance_layer_names.map!("a.ptr").array;
	inst_info.ppEnabledLayerNames = instance_layer_names.ptr;
	inst_info.enabledExtensionCount = info.instance_extension_names.length;
	auto instance_extension_names=info.instance_extension_names.map!("a.ptr").array;
	inst_info.ppEnabledExtensionNames = instance_extension_names.ptr;

	VkResult res = vkCreateInstance(&inst_info, NULL, &info.inst);
	assert(res == VK_SUCCESS);

	return res;
}

void init_device_extension_names(ref sample_info info) {
    info.device_extension_names~=VK_KHR_SWAPCHAIN_EXTENSION_NAME;
}

VkResult init_device(ref sample_info info) {
    VkResult res;
    VkDeviceQueueCreateInfo queue_info = {};

    auto queue_priorities = [0.0f];
    queue_info.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_info.pNext = NULL;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = queue_priorities.ptr;
    queue_info.queueFamilyIndex = info.graphics_queue_family_index;

    VkDeviceCreateInfo device_info = {};
    device_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_info.pNext = NULL;
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    device_info.enabledExtensionCount = info.device_extension_names.length;
	auto device_extension_names=info.device_extension_names.map!("a.ptr").array;
    device_info.ppEnabledExtensionNames = device_extension_names.ptr;
    device_info.pEnabledFeatures = NULL;

    res = vkCreateDevice(info.gpus[0], &device_info, NULL, &info.device);
    assert(res == VK_SUCCESS);

    return res;
}

VkResult init_enumerate_device(ref sample_info info, uint gpu_count=1) 
{
    const req_count = gpu_count;
    VkResult res = vkEnumeratePhysicalDevices(info.inst, &gpu_count, NULL);
    assert(gpu_count);
    info.gpus.length=gpu_count;

    res = vkEnumeratePhysicalDevices(info.inst, &gpu_count, info.gpus.ptr);
    assert(!res && gpu_count >= req_count);

    vkGetPhysicalDeviceQueueFamilyProperties(info.gpus[0],
                                             &info.queue_family_count, NULL);
    assert(info.queue_family_count >= 1);

    info.queue_props.length=info.queue_family_count;
    vkGetPhysicalDeviceQueueFamilyProperties(
											 info.gpus[0], &info.queue_family_count, info.queue_props.ptr);
    assert(info.queue_family_count >= 1);

    /* This is as good a place as any to do this */
    vkGetPhysicalDeviceMemoryProperties(info.gpus[0], &info.memory_properties);
    vkGetPhysicalDeviceProperties(info.gpus[0], &info.gpu_props);

    return res;
}

void init_queue_family_index(ref sample_info info) {
    /* This routine simply finds a graphics queue for a later vkCreateDevice,
	* without consideration for which queue family can present an image.
	* Do not use this if your intent is to present later in your sample,
	* instead use the init_connection, init_window, init_swapchain_extension,
	* init_device call sequence to get a graphics and present compatible queue
	* family
	*/

    vkGetPhysicalDeviceQueueFamilyProperties(info.gpus[0],
                                             &info.queue_family_count, NULL);
    assert(info.queue_family_count >= 1);

    info.queue_props.length=info.queue_family_count;
    vkGetPhysicalDeviceQueueFamilyProperties(
											 info.gpus[0], &info.queue_family_count, info.queue_props.ptr);
    assert(info.queue_family_count >= 1);

    bool found = false;
    for (uint i = 0; i < info.queue_family_count; i++) {
        if (info.queue_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
            info.graphics_queue_family_index = i;
            found = true;
            break;
        }
    }
    assert(found);
}

VkResult init_debug_report_callback(ref sample_info info,
                                    PFN_vkDebugReportCallbackEXT dbgFunc) 
{
	/+
	VkResult res;
	VkDebugReportCallbackEXT debug_report_callback;

	info.dbgCreateDebugReportCallback =
		cast(PFN_vkCreateDebugReportCallbackEXT)vkGetInstanceProcAddr(
																  info.inst, "vkCreateDebugReportCallbackEXT");
	if (!info.dbgCreateDebugReportCallback) {
		log( "GetInstanceProcAddr: Unable to find "
			 "vkCreateDebugReportCallbackEXT function.");
		return VK_ERROR_INITIALIZATION_FAILED;
	}
	log( "Got dbgCreateDebugReportCallback function");

	info.dbgDestroyDebugReportCallback =
		cast(PFN_vkDestroyDebugReportCallbackEXT)vkGetInstanceProcAddr(
																   info.inst, "vkDestroyDebugReportCallbackEXT");
	if (!info.dbgDestroyDebugReportCallback) {
		log( "GetInstanceProcAddr: Unable to find "
				"vkDestroyDebugReportCallbackEXT function.");
		return VK_ERROR_INITIALIZATION_FAILED;
	}
	log( "Got dbgDestroyDebugReportCallback function");

	VkDebugReportCallbackCreateInfoEXT create_info = {};
	create_info.sType = VK_STRUCTURE_TYPE_DEBUG_REPORT_CREATE_INFO_EXT;
	create_info.pNext = NULL;
	create_info.flags =
		VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT;
	create_info.pfnCallback = dbgFunc;
	create_info.pUserData = NULL;

	res = info.dbgCreateDebugReportCallback(info.inst, &create_info, NULL,
											&debug_report_callback);
	switch (res) {
		case VK_SUCCESS:
			log( "Successfully created debug report callback object");
			info.debug_report_callbacks~=debug_report_callback;
			break;
		case VK_ERROR_OUT_OF_HOST_MEMORY:
			log("dbgCreateDebugReportCallback: out of host memory pointer");
			return VkResult.VK_ERROR_INITIALIZATION_FAILED;

		default:
			log( "dbgCreateDebugReportCallback: unknown failure");
			return VkResult.VK_ERROR_INITIALIZATION_FAILED;
	}
	return res;
	+/
	return VK_SUCCESS;
}

void destroy_debug_report_callback(ref sample_info info) 
{
	/+
    while (info.debug_report_callbacks.length > 0) {
        info.dbgDestroyDebugReportCallback(
										   info.inst, info.debug_report_callbacks.back(), NULL);
        info.debug_report_callbacks.pop_back();
    }
	+/
}

void init_connection(ref sample_info info) {
}

void init_window_size(ref sample_info info, int default_width,
                      int default_height) 
{
	info.width = default_width;
	info.height = default_height;
}

void init_depth_buffer(ref sample_info info) 
{
    VkImageCreateInfo image_info = {};

    /* allow custom depth formats */
    if (info.depth.format == VK_FORMAT_UNDEFINED)
        info.depth.format = VK_FORMAT_D16_UNORM;


    const VkFormat depth_format = info.depth.format;

    VkFormatProperties props;
    vkGetPhysicalDeviceFormatProperties(info.gpus[0], depth_format, &props);
    if (props.linearTilingFeatures &
        VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) 
	{
		image_info.tiling = VK_IMAGE_TILING_LINEAR;
	} else if (props.optimalTilingFeatures &
			   VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) 
	{
		image_info.tiling = VK_IMAGE_TILING_OPTIMAL;
	} else {
		/* Try other depth formats? */
		log( "depth_format " , depth_format , " Unsupported.");
		assert(false);
	}

    image_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    image_info.pNext = NULL;
    image_info.imageType = VK_IMAGE_TYPE_2D;
    image_info.format = depth_format;
    image_info.extent.width = info.width;
    image_info.extent.height = info.height;
    image_info.extent.depth = 1;
    image_info.mipLevels = 1;
    image_info.arrayLayers = 1;
    image_info.samples = NUM_SAMPLES;
    image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    image_info.queueFamilyIndexCount = 0;
    image_info.pQueueFamilyIndices = NULL;
    image_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    image_info.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    image_info.flags = 0;

    VkMemoryAllocateInfo mem_alloc = {};
    mem_alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mem_alloc.pNext = NULL;
    mem_alloc.allocationSize = 0;
    mem_alloc.memoryTypeIndex = 0;

    VkImageViewCreateInfo view_info = {};
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

    if (depth_format == VK_FORMAT_D16_UNORM_S8_UINT ||
        depth_format == VK_FORMAT_D24_UNORM_S8_UINT ||
        depth_format == VK_FORMAT_D32_SFLOAT_S8_UINT) {
			view_info.subresourceRange.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT;
		}

    VkMemoryRequirements mem_reqs;

    /* Create image */
    auto res = vkCreateImage(info.device, &image_info, NULL, &info.depth.image);
    assert(res == VK_SUCCESS);

    vkGetImageMemoryRequirements(info.device, info.depth.image, &mem_reqs);

    mem_alloc.allocationSize = mem_reqs.size;
    /* Use the memory properties to determine the type of memory required */
    auto pass = memory_type_from_properties(info, mem_reqs.memoryTypeBits,
                                       0, /* No requirements */
                                       &mem_alloc.memoryTypeIndex);
    assert(pass);

    /* Allocate memory */
    res = vkAllocateMemory(info.device, &mem_alloc, NULL, &info.depth.mem);
    assert(res == VK_SUCCESS);

    /* Bind memory */
    res = vkBindImageMemory(info.device, info.depth.image, info.depth.mem, 0);
    assert(res == VK_SUCCESS);

    /* Set the image layout to depth stencil optimal */
    set_image_layout(info, info.depth.image,
                     view_info.subresourceRange.aspectMask,
                     VK_IMAGE_LAYOUT_UNDEFINED,
                     VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);

    /* Create image view */
    view_info.image = info.depth.image;
    res = vkCreateImageView(info.device, &view_info, NULL, &info.depth.view);
    assert(res == VK_SUCCESS);
}

void init_swapchain_extension(ref sample_info info) {
    /* DEPENDS on init_connection() and init_window() */

    VkResult res;

	// Construct the surface description:
	version(Windows){
		create_swapchain(info.inst, &info.surface, info.connection, info.window);
	}
    assert(res == VK_SUCCESS);

    // Iterate over each queue to learn whether it supports presenting:
    VkBool32[] pSupportsPresent=new VkBool32[info.queue_family_count];
    for (uint i = 0; i < info.queue_family_count; i++) {
        vkGetPhysicalDeviceSurfaceSupportKHR(info.gpus[0], i, info.surface,
                                             &pSupportsPresent[i]);
    }

    // Search for a graphics and a present queue in the array of queue
    // families, try to find one that supports both
    info.graphics_queue_family_index = uint.max;
    info.present_queue_family_index = uint.max;
    for (uint i = 0; i < info.queue_family_count; ++i) {
        if ((info.queue_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
            if (info.graphics_queue_family_index == uint.max)
                info.graphics_queue_family_index = i;

            if (pSupportsPresent[i] == VK_TRUE) {
                info.graphics_queue_family_index = i;
                info.present_queue_family_index = i;
                break;
            }
        }
    }

    if (info.present_queue_family_index == uint.max) {
        // If didn't find a queue that supports both graphics and present, then
        // find a separate present queue.
        for (size_t i = 0; i < info.queue_family_count; ++i)
            if (pSupportsPresent[i] == VK_TRUE) {
                info.present_queue_family_index = i;
                break;
            }
    }

    // Generate error if could not find queues that support graphics
    // and present
    if (info.graphics_queue_family_index == uint.max ||
        info.present_queue_family_index == uint.max) {
        log( "Could not find a queues for both graphics and present");
			assert(false);
		}

    // Get the list of VkFormats that are supported:
    uint formatCount;
    res = vkGetPhysicalDeviceSurfaceFormatsKHR(info.gpus[0], info.surface,
                                               &formatCount, NULL);
    assert(res == VK_SUCCESS);
    VkSurfaceFormatKHR[] surfFormats=new VkSurfaceFormatKHR[formatCount];
    res = vkGetPhysicalDeviceSurfaceFormatsKHR(info.gpus[0], info.surface,
                                               &formatCount, surfFormats.ptr);
    assert(res == VK_SUCCESS);
    // If the format list includes just one entry of VK_FORMAT_UNDEFINED,
    // the surface has no preferred format.  Otherwise, at least one
    // supported format will be returned.
    if (formatCount == 1 && surfFormats[0].format == VK_FORMAT_UNDEFINED) {
        info.format = VK_FORMAT_B8G8R8A8_UNORM;
    } 
	else {
        assert(formatCount >= 1);
        info.format = surfFormats[0].format;
    }
}

void init_presentable_image(ref sample_info info) 
{
    /* DEPENDS on init_swap_chain() */

    VkSemaphoreCreateInfo imageAcquiredSemaphoreCreateInfo;
    imageAcquiredSemaphoreCreateInfo.sType =
        VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    imageAcquiredSemaphoreCreateInfo.pNext = NULL;
    imageAcquiredSemaphoreCreateInfo.flags = 0;

    auto res = vkCreateSemaphore(info.device, &imageAcquiredSemaphoreCreateInfo,
                            NULL, &info.imageAcquiredSemaphore);
    assert(!res);

    // Get the index of the next available swapchain image:
    res = vkAcquireNextImageKHR(info.device, info.swap_chain, ulong.max,
                                info.imageAcquiredSemaphore, VkFence.init,
                                &info.current_buffer);
    // TODO: Deal with the VK_SUBOPTIMAL_KHR and VK_ERROR_OUT_OF_DATE_KHR
    // return codes
    assert(!res);

    set_image_layout(info, info.buffers[info.current_buffer].image,
                     VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_UNDEFINED,
                     VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
}

void execute_queue_cmdbuf(ref sample_info info,
                          const VkCommandBuffer *cmd_bufs,
                          ref VkFence fence) 
{
	VkPipelineStageFlags pipe_stage_flags =
		VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
	VkSubmitInfo[1] submit_info;
	submit_info[0].pNext = NULL;
	submit_info[0].sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
	submit_info[0].waitSemaphoreCount = 1;
	submit_info[0].pWaitSemaphores = &info.imageAcquiredSemaphore;
	submit_info[0].pWaitDstStageMask = NULL;
	submit_info[0].commandBufferCount = 1;
	submit_info[0].pCommandBuffers = cmd_bufs;
	submit_info[0].pWaitDstStageMask = &pipe_stage_flags;
	submit_info[0].signalSemaphoreCount = 0;
	submit_info[0].pSignalSemaphores = NULL;

	/* Queue the command buffer for execution */
	auto res = vkQueueSubmit(info.graphics_queue, 1, submit_info.ptr, fence);
	assert(!res);
}
void execute_pre_present_barrier(ref sample_info info) {
    /* DEPENDS on init_swap_chain() */
    /* Add mem barrier to change layout to present */

    VkImageMemoryBarrier prePresentBarrier = {};
    prePresentBarrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    prePresentBarrier.pNext = NULL;
    prePresentBarrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    prePresentBarrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
    prePresentBarrier.oldLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    prePresentBarrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    prePresentBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    prePresentBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    prePresentBarrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    prePresentBarrier.subresourceRange.baseMipLevel = 0;
    prePresentBarrier.subresourceRange.levelCount = 1;
    prePresentBarrier.subresourceRange.baseArrayLayer = 0;
    prePresentBarrier.subresourceRange.layerCount = 1;
    prePresentBarrier.image = info.buffers[info.current_buffer].image;
    vkCmdPipelineBarrier(info.cmd,
                         VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                         VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0,
                         NULL, 1, &prePresentBarrier);
}
void execute_present_image(ref sample_info info) 
{
    /* DEPENDS on init_presentable_image() and init_swap_chain()*/
    /* Present the image in the window */

    VkPresentInfoKHR present;
    present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present.pNext = NULL;
    present.swapchainCount = 1;
    present.pSwapchains = &info.swap_chain;
    present.pImageIndices = &info.current_buffer;
    present.pWaitSemaphores = NULL;
    present.waitSemaphoreCount = 0;
    present.pResults = NULL;

    auto res = vkQueuePresentKHR(info.present_queue, &present);
    // TODO: Deal with the VK_SUBOPTIMAL_WSI and VK_ERROR_OUT_OF_DATE_WSI
    // return codes
    assert(!res);
}

void init_swap_chain(ref sample_info info, VkImageUsageFlags usageFlags= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
					 VK_IMAGE_USAGE_TRANSFER_SRC_BIT) 
{
    /* DEPENDS on info.cmd and info.queue initialized */

    
    VkSurfaceCapabilitiesKHR surfCapabilities;

    auto res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(info.gpus[0], info.surface,
                                                    &surfCapabilities);
    assert(res == VK_SUCCESS);

    uint presentModeCount;
    res = vkGetPhysicalDeviceSurfacePresentModesKHR(info.gpus[0], info.surface,
                                                    &presentModeCount, NULL);
    assert(res == VK_SUCCESS);
    VkPresentModeKHR[] presentModes=new VkPresentModeKHR[presentModeCount];
    assert(presentModes);
    res = vkGetPhysicalDeviceSurfacePresentModesKHR(
													info.gpus[0], info.surface, &presentModeCount, presentModes.ptr);
    assert(res == VK_SUCCESS);

    VkExtent2D swapchainExtent;
    // width and height are either both 0xFFFFFFFF, or both not 0xFFFFFFFF.
    if (surfCapabilities.currentExtent.width == 0xFFFFFFFF) {
        // If the surface size is undefined, the size is set to
        // the size of the images requested.
        swapchainExtent.width = info.width;
        swapchainExtent.height = info.height;
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
    } else {
        // If the surface size is defined, the swap chain size must match
        swapchainExtent = surfCapabilities.currentExtent;
    }

    // If mailbox mode is available, use it, as is the lowest-latency non-
    // tearing mode.  If not, try IMMEDIATE which will usually be available,
    // and is fastest (though it tears).  If not, fall back to FIFO which is
    // always available.
    VkPresentModeKHR swapchainPresentMode = VK_PRESENT_MODE_FIFO_KHR;
    for (size_t i = 0; i < presentModeCount; i++) {
        if (presentModes[i] == VK_PRESENT_MODE_MAILBOX_KHR) {
            swapchainPresentMode = VK_PRESENT_MODE_MAILBOX_KHR;
            break;
        }
        if ((swapchainPresentMode != VK_PRESENT_MODE_MAILBOX_KHR) &&
            (presentModes[i] == VK_PRESENT_MODE_IMMEDIATE_KHR)) {
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
        VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR) {
			preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
		} else {
			preTransform = surfCapabilities.currentTransform;
		}

    VkSwapchainCreateInfoKHR swapchain_ci = {};
    swapchain_ci.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    swapchain_ci.pNext = NULL;
    swapchain_ci.surface = info.surface;
    swapchain_ci.minImageCount = desiredNumberOfSwapChainImages;
    swapchain_ci.imageFormat = info.format;
    swapchain_ci.imageExtent.width = swapchainExtent.width;
    swapchain_ci.imageExtent.height = swapchainExtent.height;
    swapchain_ci.preTransform = preTransform;
    swapchain_ci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    swapchain_ci.imageArrayLayers = 1;
    swapchain_ci.presentMode = swapchainPresentMode;
    //swapchain_ci.oldSwapchain = VK_NULL_HANDLE;
    swapchain_ci.clipped = false;
    swapchain_ci.imageColorSpace = VK_COLORSPACE_SRGB_NONLINEAR_KHR;
    swapchain_ci.imageUsage = usageFlags;
    swapchain_ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    swapchain_ci.queueFamilyIndexCount = 0;
    swapchain_ci.pQueueFamilyIndices = NULL;
    auto queueFamilyIndices = [
        cast(uint)info.graphics_queue_family_index,
        cast(uint)info.present_queue_family_index
	];
	if (info.graphics_queue_family_index != info.present_queue_family_index) {
		// If the graphics and present queues are from different queue families,
		// we either have to explicitly transfer ownership of images between the
		// queues, or we have to create the swapchain with imageSharingMode
		// as VK_SHARING_MODE_CONCURRENT
		swapchain_ci.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
		swapchain_ci.queueFamilyIndexCount = 2;
		swapchain_ci.pQueueFamilyIndices = queueFamilyIndices.ptr;
	}

	res = vkCreateSwapchainKHR(info.device, &swapchain_ci, NULL,
							   &info.swap_chain);
	assert(res == VK_SUCCESS);

	res = vkGetSwapchainImagesKHR(info.device, info.swap_chain,
								  &info.swapchainImageCount, NULL);
	assert(res == VK_SUCCESS);

	VkImage[] swapchainImages=new VkImage[info.swapchainImageCount];
	assert(swapchainImages);
	res = vkGetSwapchainImagesKHR(info.device, info.swap_chain,
								  &info.swapchainImageCount, swapchainImages.ptr);
	assert(res == VK_SUCCESS);

	for (uint i = 0; i < info.swapchainImageCount; i++) {
		swap_chain_buffer sc_buffer;

		VkImageViewCreateInfo color_image_view = {};
		color_image_view.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
		color_image_view.pNext = NULL;
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
		color_image_view.viewType = VK_IMAGE_VIEW_TYPE_2D;
		color_image_view.flags = 0;

		sc_buffer.image = swapchainImages[i];

		color_image_view.image = sc_buffer.image;

		res = vkCreateImageView(info.device, &color_image_view, NULL,
								&sc_buffer.view);
		info.buffers~=sc_buffer;
		assert(res == VK_SUCCESS);
	}

	info.current_buffer = 0;
}

void init_uniform_buffer(ref sample_info info) 
{
    float fov = radians(45.0f);
    if (info.width > info.height) {
        fov *= cast(float)info.height / cast(float)info.width;
    }
	/*
    info.Projection = perspective(fov,
                                       cast(float)info.width /
										   cast(float)info.height, 0.1f, 100.0f);

    info.View = lookAt(
							vec3(-5, 3,-10),  // Camera is at (-5,3,-10), in World Space
							vec3( 0, 0,  0),  // and looks at the origin
							vec3( 0,-1,  0)   // Head is up (set to 0,-1,0 to look upside-down)
							);
	*/
    info.Model = mat4!float.identity;
    // Vulkan clip space has inverted Y and half Z.
    info.Clip = mat4!float(1.0f,  0.0f, 0.0f, 0.0f,
					 0.0f, -1.0f, 0.0f, 0.0f,
					 0.0f,  0.0f, 0.5f, 0.0f,
					 0.0f,  0.0f, 0.5f, 1.0f);

    info.MVP = info.Clip * info.Projection * info.View * info.Model;

    /* VULKAN_KEY_START */
    VkBufferCreateInfo buf_info = {};
    buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buf_info.pNext = NULL;
    buf_info.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    buf_info.size = info.MVP.sizeof;
    buf_info.queueFamilyIndexCount = 0;
    buf_info.pQueueFamilyIndices = NULL;
    buf_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    buf_info.flags = 0;
    auto res = vkCreateBuffer(info.device, &buf_info, NULL, &info.uniform_data.buf);
    assert(res == VK_SUCCESS);

    VkMemoryRequirements mem_reqs;
    vkGetBufferMemoryRequirements(info.device, info.uniform_data.buf,
                                  &mem_reqs);

    VkMemoryAllocateInfo alloc_info = {};
    alloc_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.pNext = NULL;
    alloc_info.memoryTypeIndex = 0;

    alloc_info.allocationSize = mem_reqs.size;
    auto pass = memory_type_from_properties(info, mem_reqs.memoryTypeBits,
                                       VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
									   VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                                       &alloc_info.memoryTypeIndex);
    assert(pass && "No mappable, coherent memory");

    res = vkAllocateMemory(info.device, &alloc_info, NULL,
                           &(info.uniform_data.mem));
    assert(res == VK_SUCCESS);

    uint8_t *pData;
    res = vkMapMemory(info.device, info.uniform_data.mem, 0, mem_reqs.size, 0,
                      cast(void **)&pData);
    assert(res == VK_SUCCESS);

    memcpy(pData, &info.MVP, info.MVP.sizeof);

    vkUnmapMemory(info.device, info.uniform_data.mem);

    res = vkBindBufferMemory(info.device, info.uniform_data.buf,
                             info.uniform_data.mem, 0);
    assert(res == VK_SUCCESS);

    info.uniform_data.buffer_info.buffer = info.uniform_data.buf;
    info.uniform_data.buffer_info.offset = 0;
    info.uniform_data.buffer_info.range = info.MVP.sizeof;
}

void init_descriptor_and_pipeline_layouts(ref sample_info info,
                                          bool use_texture) 
{
	VkDescriptorSetLayoutBinding[2] layout_bindings;
	layout_bindings[0].binding = 0;
	layout_bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
	layout_bindings[0].descriptorCount = 1;
	layout_bindings[0].stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
	layout_bindings[0].pImmutableSamplers = NULL;

	if (use_texture) {
		layout_bindings[1].binding = 1;
		layout_bindings[1].descriptorType =
			VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
		layout_bindings[1].descriptorCount = 1;
		layout_bindings[1].stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
		layout_bindings[1].pImmutableSamplers = NULL;
	}

	/* Next take layout bindings and use them to create a descriptor set layout
	*/
	VkDescriptorSetLayoutCreateInfo descriptor_layout = {};
	descriptor_layout.sType =
		VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
	descriptor_layout.pNext = NULL;
	descriptor_layout.bindingCount = use_texture ? 2 : 1;
	descriptor_layout.pBindings = layout_bindings.ptr;



	info.desc_layout.length=NUM_DESCRIPTOR_SETS;
	auto res = vkCreateDescriptorSetLayout(info.device, &descriptor_layout, NULL,
									  info.desc_layout.ptr);
	assert(res == VK_SUCCESS);

	/* Now use the descriptor layout to create a pipeline layout */
	VkPipelineLayoutCreateInfo pPipelineLayoutCreateInfo = {};
	pPipelineLayoutCreateInfo.sType =
		VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
	pPipelineLayoutCreateInfo.pNext = NULL;
	pPipelineLayoutCreateInfo.pushConstantRangeCount = 0;
	pPipelineLayoutCreateInfo.pPushConstantRanges = NULL;
	pPipelineLayoutCreateInfo.setLayoutCount = NUM_DESCRIPTOR_SETS;
	pPipelineLayoutCreateInfo.pSetLayouts = info.desc_layout.ptr;

	res = vkCreatePipelineLayout(info.device, &pPipelineLayoutCreateInfo, NULL,
								 &info.pipeline_layout);
	assert(res == VK_SUCCESS);
}

void init_renderpass(ref sample_info info, bool include_depth, bool clear=true,
                     VkImageLayout finalLayout= VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) 
{
	/* DEPENDS on init_swap_chain() and init_depth_buffer() */


	/* Need attachments for render target and depth buffer */
	VkAttachmentDescription[2] attachments;
	attachments[0].format = info.format;
	attachments[0].samples = NUM_SAMPLES;
	attachments[0].loadOp =
		clear ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_DONT_CARE;
	attachments[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
	attachments[0].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
	attachments[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
	attachments[0].initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
	attachments[0].finalLayout = finalLayout;
	attachments[0].flags = 0;

	if (include_depth) {
		attachments[1].format = info.depth.format;
		attachments[1].samples = NUM_SAMPLES;
		attachments[1].loadOp = clear ? VK_ATTACHMENT_LOAD_OP_CLEAR
			: VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		attachments[1].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		attachments[1].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_LOAD;
		attachments[1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_STORE;
		attachments[1].initialLayout =
			VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		attachments[1].finalLayout =
			VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		attachments[1].flags = 0;
	}

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
	subpass.pDepthStencilAttachment = include_depth ? &depth_reference : NULL;
	subpass.preserveAttachmentCount = 0;
	subpass.pPreserveAttachments = NULL;

	VkRenderPassCreateInfo rp_info = {};
	rp_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
	rp_info.pNext = NULL;
	rp_info.attachmentCount = include_depth ? 2 : 1;
	rp_info.pAttachments = attachments.ptr;
	rp_info.subpassCount = 1;
	rp_info.pSubpasses = &subpass;
	rp_info.dependencyCount = 0;
	rp_info.pDependencies = NULL;

	auto res = vkCreateRenderPass(info.device, &rp_info, NULL, &info.render_pass);
	assert(res == VK_SUCCESS);
}

void init_framebuffers(ref sample_info info, bool include_depth) {
    /* DEPENDS on init_depth_buffer(), init_renderpass() and
	* init_swapchain_extension() */

    
    VkImageView[2] attachments;
    attachments[1] = info.depth.view;

    VkFramebufferCreateInfo fb_info;
    fb_info.renderPass = info.render_pass;
    fb_info.attachmentCount = include_depth ? 2 : 1;
    fb_info.pAttachments = attachments.ptr;
    fb_info.width = info.width;
    fb_info.height = info.height;
    fb_info.layers = 1;

    info.framebuffers.length=info.swapchainImageCount;
    for (uint i = 0; i < info.swapchainImageCount; i++) {
        attachments[0] = info.buffers[i].view;
        auto res = vkCreateFramebuffer(info.device, &fb_info, NULL,
                                  &info.framebuffers[i]);
        assert(res == VK_SUCCESS);
    }
}
void init_command_pool(ref sample_info info) {
    /* DEPENDS on init_swapchain_extension() */
    

    VkCommandPoolCreateInfo cmd_pool_info = {};
    cmd_pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cmd_pool_info.pNext = NULL;
    cmd_pool_info.queueFamilyIndex = info.graphics_queue_family_index;
    cmd_pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;

    auto res =
        vkCreateCommandPool(info.device, &cmd_pool_info, NULL, &info.cmd_pool);
    assert(res == VK_SUCCESS);
}

void init_command_buffer(ref sample_info info) {
    /* DEPENDS on init_swapchain_extension() and init_command_pool() */
    

    VkCommandBufferAllocateInfo cmd = {};
    cmd.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmd.pNext = NULL;
    cmd.commandPool = info.cmd_pool;
    cmd.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmd.commandBufferCount = 1;

    auto res = vkAllocateCommandBuffers(info.device, &cmd, &info.cmd);
    assert(res == VK_SUCCESS);
}
void execute_begin_command_buffer(ref sample_info info) {
    /* DEPENDS on init_command_buffer() */
    

    VkCommandBufferBeginInfo cmd_buf_info = {};
    cmd_buf_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    cmd_buf_info.pNext = NULL;
    cmd_buf_info.flags = 0;
    cmd_buf_info.pInheritanceInfo = NULL;

    auto res = vkBeginCommandBuffer(info.cmd, &cmd_buf_info);
    assert(res == VK_SUCCESS);
}

void execute_end_command_buffer(ref sample_info info) {
    

    auto res = vkEndCommandBuffer(info.cmd);
    assert(res == VK_SUCCESS);
}

void execute_queue_command_buffer(ref sample_info info) {
    

    /* Queue the command buffer for execution */
    const VkCommandBuffer[] cmd_bufs = [info.cmd];
    VkFenceCreateInfo fenceInfo;
    VkFence drawFence;
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.pNext = NULL;
    fenceInfo.flags = 0;
    vkCreateFence(info.device, &fenceInfo, NULL, &drawFence);

    VkPipelineStageFlags pipe_stage_flags =
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo[1] submit_info;
    submit_info[0].pNext = NULL;
    submit_info[0].sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit_info[0].waitSemaphoreCount = 0;
    submit_info[0].pWaitSemaphores = NULL;
    submit_info[0].pWaitDstStageMask = &pipe_stage_flags;
    submit_info[0].commandBufferCount = 1;
    submit_info[0].pCommandBuffers = cmd_bufs.ptr;
    submit_info[0].signalSemaphoreCount = 0;
    submit_info[0].pSignalSemaphores = NULL;

    auto res = vkQueueSubmit(info.graphics_queue, 1, submit_info.ptr, drawFence);
    assert(res == VK_SUCCESS);

    do {
        res =
            vkWaitForFences(info.device, 1, &drawFence, VK_TRUE, FENCE_TIMEOUT);
    } while (res == VK_TIMEOUT);
    assert(res == VK_SUCCESS);

    vkDestroyFence(info.device, drawFence, NULL);
}

void init_device_queue(ref sample_info info) {
    /* DEPENDS on init_swapchain_extension() */

    vkGetDeviceQueue(info.device, info.graphics_queue_family_index, 0,
                     &info.graphics_queue);
    if (info.graphics_queue_family_index == info.present_queue_family_index) {
        info.present_queue = info.graphics_queue;
    } else {
        vkGetDeviceQueue(info.device, info.present_queue_family_index, 0,
                         &info.present_queue);
    }
}

void init_vertex_buffer(ref sample_info info, const void *vertexData,
                        uint dataSize, uint dataStride,
                        bool use_texture) 
{
	VkBufferCreateInfo buf_info = {};
	buf_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
	buf_info.pNext = NULL;
	buf_info.usage = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
	buf_info.size = dataSize;
	buf_info.queueFamilyIndexCount = 0;
	buf_info.pQueueFamilyIndices = NULL;
	buf_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	buf_info.flags = 0;
	auto res = vkCreateBuffer(info.device, &buf_info, NULL, &info.vertex_buffer.buf);
	assert(res == VK_SUCCESS);

	VkMemoryRequirements mem_reqs;
	vkGetBufferMemoryRequirements(info.device, info.vertex_buffer.buf,
								  &mem_reqs);

	VkMemoryAllocateInfo alloc_info = {};
	alloc_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
	alloc_info.pNext = NULL;
	alloc_info.memoryTypeIndex = 0;

	alloc_info.allocationSize = mem_reqs.size;
	auto pass = memory_type_from_properties(info, mem_reqs.memoryTypeBits,
									   VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
									   VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
									   &alloc_info.memoryTypeIndex);
	assert(pass && "No mappable, coherent memory");

	res = vkAllocateMemory(info.device, &alloc_info, NULL,
						   &(info.vertex_buffer.mem));
	assert(res == VK_SUCCESS);
	info.vertex_buffer.buffer_info.range = mem_reqs.size;
	info.vertex_buffer.buffer_info.offset = 0;

	uint8_t *pData;
	res = vkMapMemory(info.device, info.vertex_buffer.mem, 0, mem_reqs.size, 0,
					  cast(void **)&pData);
	assert(res == VK_SUCCESS);

	memcpy(pData, vertexData, dataSize);

	vkUnmapMemory(info.device, info.vertex_buffer.mem);

	res = vkBindBufferMemory(info.device, info.vertex_buffer.buf,
							 info.vertex_buffer.mem, 0);
	assert(res == VK_SUCCESS);

	info.vi_binding.binding = 0;
	info.vi_binding.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;
	info.vi_binding.stride = dataStride;

	info.vi_attribs[0].binding = 0;
	info.vi_attribs[0].location = 0;
	info.vi_attribs[0].format = VK_FORMAT_R32G32B32A32_SFLOAT;
	info.vi_attribs[0].offset = 0;
	info.vi_attribs[1].binding = 0;
	info.vi_attribs[1].location = 1;
	info.vi_attribs[1].format =
		use_texture ? VK_FORMAT_R32G32_SFLOAT : VK_FORMAT_R32G32B32A32_SFLOAT;
	info.vi_attribs[1].offset = 16;
}

void init_descriptor_pool(ref sample_info info, bool use_texture) {
    /* DEPENDS on init_uniform_buffer() and
	* init_descriptor_and_pipeline_layouts() */

    
    VkDescriptorPoolSize[2] type_count;
    type_count[0].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    type_count[0].descriptorCount = 1;
    if (use_texture) {
        type_count[1].type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        type_count[1].descriptorCount = 1;
    }

    VkDescriptorPoolCreateInfo descriptor_pool = {};
    descriptor_pool.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    descriptor_pool.pNext = NULL;
    descriptor_pool.maxSets = 1;
    descriptor_pool.poolSizeCount = use_texture ? 2 : 1;
    descriptor_pool.pPoolSizes = type_count.ptr;

    auto res = vkCreateDescriptorPool(info.device, &descriptor_pool, NULL,
                                 &info.desc_pool);
    assert(res == VK_SUCCESS);
}

void init_descriptor_set(ref sample_info info, bool use_texture) {
    /* DEPENDS on init_descriptor_pool() */

    

    VkDescriptorSetAllocateInfo[1] alloc_info;
    alloc_info[0].sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    alloc_info[0].pNext = NULL;
    alloc_info[0].descriptorPool = info.desc_pool;
    alloc_info[0].descriptorSetCount = NUM_DESCRIPTOR_SETS;
    alloc_info[0].pSetLayouts = info.desc_layout.ptr;

    info.desc_set.length=NUM_DESCRIPTOR_SETS;
    auto res =
        vkAllocateDescriptorSets(info.device, alloc_info.ptr, info.desc_set.ptr);
    assert(res == VK_SUCCESS);

    VkWriteDescriptorSet[2] writes;


    writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[0].pNext = NULL;
    writes[0].dstSet = info.desc_set[0];
    writes[0].descriptorCount = 1;
    writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    writes[0].pBufferInfo = &info.uniform_data.buffer_info;
    writes[0].dstArrayElement = 0;
    writes[0].dstBinding = 0;

    if (use_texture) {
        writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[1].dstSet = info.desc_set[0];
        writes[1].dstBinding = 1;
        writes[1].descriptorCount = 1;
        writes[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        writes[1].pImageInfo = &info.texture_data.image_info;
        writes[1].dstArrayElement = 0;
    }

    vkUpdateDescriptorSets(info.device, use_texture ? 2 : 1, writes.ptr, 0, NULL);
}

void init_shaders(ref sample_info info, string vertShader, string fragShader)
{
	//init_glslang();
	VkShaderModuleCreateInfo moduleCreateInfo;

	if (vertShader) {
		auto vtx_spv=read(vertShader);
		info.shaderStages[0].sType =
			VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
		info.shaderStages[0].pNext = NULL;
		info.shaderStages[0].pSpecializationInfo = NULL;
		info.shaderStages[0].flags = 0;
		info.shaderStages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
		info.shaderStages[0].pName = "main";

		moduleCreateInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
		moduleCreateInfo.pNext = NULL;
		moduleCreateInfo.flags = 0;
		moduleCreateInfo.codeSize = vtx_spv.length;
		moduleCreateInfo.pCode = cast(uint*)vtx_spv.ptr;
		auto res = vkCreateShaderModule(info.device, &moduleCreateInfo, NULL,
								   &info.shaderStages[0]._module);
		assert(res == VK_SUCCESS);
	}

	if (fragShader) {
		auto frag_spv=read(fragShader);
		info.shaderStages[1].sType =
			VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
		info.shaderStages[1].pNext = NULL;
		info.shaderStages[1].pSpecializationInfo = NULL;
		info.shaderStages[1].flags = 0;
		info.shaderStages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
		info.shaderStages[1].pName = "main";

		moduleCreateInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
		moduleCreateInfo.pNext = NULL;
		moduleCreateInfo.flags = 0;
		moduleCreateInfo.codeSize = frag_spv.length;
		moduleCreateInfo.pCode = cast(uint*)frag_spv.ptr;
		auto res = vkCreateShaderModule(info.device, &moduleCreateInfo, NULL,
								   &info.shaderStages[1]._module);
		assert(res == VK_SUCCESS);
	}
}

void init_pipeline_cache(ref sample_info info) {
    

    VkPipelineCacheCreateInfo pipelineCache;
    pipelineCache.sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
    pipelineCache.pNext = NULL;
    pipelineCache.initialDataSize = 0;
    pipelineCache.pInitialData = NULL;
    pipelineCache.flags = 0;
    auto res = vkCreatePipelineCache(info.device, &pipelineCache, NULL,
                                &info.pipelineCache);
    assert(res == VK_SUCCESS);
}

void init_pipeline(ref sample_info info, VkBool32 include_depth,
                   VkBool32 include_vi=true) 
{
	VkDynamicState[VkDynamicState.max+1] dynamicStateEnables;
	VkPipelineDynamicStateCreateInfo dynamicState = {};
	memset(dynamicStateEnables.ptr, 0, dynamicStateEnables.sizeof);
	dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
	dynamicState.pNext = NULL;
	dynamicState.pDynamicStates = dynamicStateEnables.ptr;
	dynamicState.dynamicStateCount = 0;

	VkPipelineVertexInputStateCreateInfo vi;
	if (include_vi) {
		vi.pNext = NULL;
		vi.flags = 0;
		vi.vertexBindingDescriptionCount = 1;
		vi.pVertexBindingDescriptions = &info.vi_binding;
		vi.vertexAttributeDescriptionCount = 2;
		vi.pVertexAttributeDescriptions = info.vi_attribs.ptr;
	}
	VkPipelineInputAssemblyStateCreateInfo ia;
	ia.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
	ia.pNext = NULL;
	ia.flags = 0;
	ia.primitiveRestartEnable = VK_FALSE;
	ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

	VkPipelineRasterizationStateCreateInfo rs;
	rs.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
	rs.pNext = NULL;
	rs.flags = 0;
	rs.polygonMode = VK_POLYGON_MODE_FILL;
	rs.cullMode = VK_CULL_MODE_BACK_BIT;
	rs.frontFace = VK_FRONT_FACE_CLOCKWISE;
	rs.depthClampEnable = include_depth;
	rs.rasterizerDiscardEnable = VK_FALSE;
	rs.depthBiasEnable = VK_FALSE;
	rs.depthBiasConstantFactor = 0;
	rs.depthBiasClamp = 0;
	rs.depthBiasSlopeFactor = 0;
	rs.lineWidth = 1.0f;

	VkPipelineColorBlendStateCreateInfo cb;
	cb.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
	cb.flags = 0;
	cb.pNext = NULL;
	VkPipelineColorBlendAttachmentState[1] att_state;
	att_state[0].colorWriteMask = 0xf;
	att_state[0].blendEnable = VK_FALSE;
	att_state[0].alphaBlendOp = VK_BLEND_OP_ADD;
	att_state[0].colorBlendOp = VK_BLEND_OP_ADD;
	att_state[0].srcColorBlendFactor = VK_BLEND_FACTOR_ZERO;
	att_state[0].dstColorBlendFactor = VK_BLEND_FACTOR_ZERO;
	att_state[0].srcAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
	att_state[0].dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
	cb.attachmentCount = 1;
	cb.pAttachments = att_state.ptr;
	cb.logicOpEnable = VK_FALSE;
	cb.logicOp = VK_LOGIC_OP_NO_OP;
	cb.blendConstants[0] = 1.0f;
	cb.blendConstants[1] = 1.0f;
	cb.blendConstants[2] = 1.0f;
	cb.blendConstants[3] = 1.0f;

	VkPipelineViewportStateCreateInfo vp;
	// Temporary disabling dynamic viewport on Android because some of drivers doesn't
	// support the feature.
	VkViewport viewports;
	viewports.minDepth = 0.0f;
	viewports.maxDepth = 1.0f;
	viewports.x = 0;
	viewports.y = 0;
	viewports.width = info.width;
	viewports.height = info.height;
	VkRect2D scissor;
	scissor.extent.width = info.width;
	scissor.extent.height = info.height;
	scissor.offset.x = 0;
	scissor.offset.y = 0;
	vp.viewportCount = NUM_VIEWPORTS;
	vp.scissorCount = NUM_SCISSORS;
	vp.pScissors = &scissor;
	vp.pViewports = &viewports;

	VkPipelineDepthStencilStateCreateInfo ds;
	ds.depthTestEnable = include_depth;
	ds.depthWriteEnable = include_depth;
	ds.depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL;
	ds.depthBoundsTestEnable = VK_FALSE;
	ds.stencilTestEnable = VK_FALSE;
	ds.back.failOp = VK_STENCIL_OP_KEEP;
	ds.back.passOp = VK_STENCIL_OP_KEEP;
	ds.back.compareOp = VK_COMPARE_OP_ALWAYS;
	ds.back.compareMask = 0;
	ds.back.reference = 0;
	ds.back.depthFailOp = VK_STENCIL_OP_KEEP;
	ds.back.writeMask = 0;
	ds.minDepthBounds = 0;
	ds.maxDepthBounds = 0;
	ds.stencilTestEnable = VK_FALSE;
	ds.front = ds.back;

	VkPipelineMultisampleStateCreateInfo ms;
	ms.pSampleMask = NULL;
	ms.rasterizationSamples = NUM_SAMPLES;
	ms.sampleShadingEnable = VK_FALSE;
	ms.alphaToCoverageEnable = VK_FALSE;
	ms.alphaToOneEnable = VK_FALSE;
	ms.minSampleShading = 0.0;

	VkGraphicsPipelineCreateInfo pipeline;
	pipeline.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
	pipeline.pNext = NULL;
	pipeline.layout = info.pipeline_layout;
	//pipeline.basePipelineHandle = VK_NULL_HANDLE;
	pipeline.basePipelineIndex = 0;
	pipeline.flags = 0;
	pipeline.pVertexInputState = &vi;
	pipeline.pInputAssemblyState = &ia;
	pipeline.pRasterizationState = &rs;
	pipeline.pColorBlendState = &cb;
	pipeline.pTessellationState = NULL;
	pipeline.pMultisampleState = &ms;
	pipeline.pDynamicState = &dynamicState;
	pipeline.pViewportState = &vp;
	pipeline.pDepthStencilState = &ds;
	pipeline.pStages = info.shaderStages.ptr;
	pipeline.stageCount = 2;
	pipeline.renderPass = info.render_pass;
	pipeline.subpass = 0;

	auto res = vkCreateGraphicsPipelines(info.device, info.pipelineCache, 1,
									&pipeline, NULL, &info.pipeline);
	assert(res == VK_SUCCESS);
}

void init_sampler(ref sample_info info, ref VkSampler sampler) 
{
    VkSamplerCreateInfo samplerCreateInfo = {};
    samplerCreateInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    samplerCreateInfo.magFilter = VK_FILTER_NEAREST;
    samplerCreateInfo.minFilter = VK_FILTER_NEAREST;
    samplerCreateInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
    samplerCreateInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerCreateInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerCreateInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerCreateInfo.mipLodBias = 0.0;
    samplerCreateInfo.anisotropyEnable = VK_FALSE,
		samplerCreateInfo.maxAnisotropy = 0;
    samplerCreateInfo.compareOp = VK_COMPARE_OP_NEVER;
    samplerCreateInfo.minLod = 0.0;
    samplerCreateInfo.maxLod = 0.0;
    samplerCreateInfo.compareEnable = VK_FALSE;
    samplerCreateInfo.borderColor = VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE;

    /* create sampler */
    auto res = vkCreateSampler(info.device, &samplerCreateInfo, NULL, &sampler);
    assert(res == VK_SUCCESS);
}

void init_image(ref sample_info info, ref texture_object texObj,
                string textureName, VkImageUsageFlags extraUsages,
                VkFormatFeatureFlags extraFeatures) 
{
	/+
	auto filename = get_base_data_dir();

	if (textureName == nullptr)
		filename.append("lunarg.ppm");
	else
		filename.append(textureName);

	if (!read_ppm(filename.c_str(), texObj.tex_width, texObj.tex_height, 0,
				  NULL)) 
	{
		log( "Could not read texture file lunarg.ppm");
		assert(false);
	}

	VkFormatProperties formatProps;
	vkGetPhysicalDeviceFormatProperties(info.gpus[0], VK_FORMAT_R8G8B8A8_UNORM,
										&formatProps);

	/* See if we can use a linear tiled image for a texture, if not, we will
	* need a staging image for the texture data */
	VkFormatFeatureFlags allFeatures =
		(VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT | extraFeatures);
	bool needStaging =
		((formatProps.linearTilingFeatures & allFeatures) != allFeatures)
		? true
			: false;

	if (needStaging) {
		assert((formatProps.optimalTilingFeatures & allFeatures) ==
			   allFeatures);
	}

	VkImageCreateInfo image_create_info = {};
	image_create_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
	image_create_info.pNext = NULL;
	image_create_info.imageType = VK_IMAGE_TYPE_2D;
	image_create_info.format = VK_FORMAT_R8G8B8A8_UNORM;
	image_create_info.extent.width = texObj.tex_width;
	image_create_info.extent.height = texObj.tex_height;
	image_create_info.extent.depth = 1;
	image_create_info.mipLevels = 1;
	image_create_info.arrayLayers = 1;
	image_create_info.samples = NUM_SAMPLES;
	image_create_info.tiling = VK_IMAGE_TILING_LINEAR;
	image_create_info.initialLayout = VK_IMAGE_LAYOUT_PREINITIALIZED;
	image_create_info.usage =
		needStaging ? (VK_IMAGE_USAGE_TRANSFER_SRC_BIT | extraUsages)
		: (VK_IMAGE_USAGE_SAMPLED_BIT | extraUsages);
	image_create_info.queueFamilyIndexCount = 0;
	image_create_info.pQueueFamilyIndices = NULL;
	image_create_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	image_create_info.flags = 0;

	VkMemoryAllocateInfo mem_alloc = {};
	mem_alloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
	mem_alloc.pNext = NULL;
	mem_alloc.allocationSize = 0;
	mem_alloc.memoryTypeIndex = 0;

	VkImage mappableImage;
	VkDeviceMemory mappableMemory;

	VkMemoryRequirements mem_reqs;

	/* Create a mappable image.  It will be the texture if linear images are ok
	* to be textures or it will be the staging image if they are not. */
	res = vkCreateImage(info.device, &image_create_info, NULL, &mappableImage);
	assert(res == VK_SUCCESS);

	vkGetImageMemoryRequirements(info.device, mappableImage, &mem_reqs);
	assert(res == VK_SUCCESS);

	mem_alloc.allocationSize = mem_reqs.size;

	/* Find the memory type that is host mappable */
	pass = memory_type_from_properties(info, mem_reqs.memoryTypeBits,
									   VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
									   VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
									   &mem_alloc.memoryTypeIndex);
	assert(pass && "No mappable, coherent memory");

	/* allocate memory */
	res = vkAllocateMemory(info.device, &mem_alloc, NULL, &(mappableMemory));
	assert(res == VK_SUCCESS);

	/* bind memory */
	res = vkBindImageMemory(info.device, mappableImage, mappableMemory, 0);
	assert(res == VK_SUCCESS);

	set_image_layout(info, mappableImage, VK_IMAGE_ASPECT_COLOR_BIT,
					 VK_IMAGE_LAYOUT_PREINITIALIZED, VK_IMAGE_LAYOUT_GENERAL);

	res = vkEndCommandBuffer(info.cmd);
	assert(res == VK_SUCCESS);
	const VkCommandBuffer cmd_bufs[] = {info.cmd};
	VkFenceCreateInfo fenceInfo;
	VkFence cmdFence;
	fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
	fenceInfo.pNext = NULL;
	fenceInfo.flags = 0;
	vkCreateFence(info.device, &fenceInfo, NULL, &cmdFence);

	VkSubmitInfo submit_info[1] = {};
	submit_info[0].pNext = NULL;
	submit_info[0].sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
	submit_info[0].waitSemaphoreCount = 0;
	submit_info[0].pWaitSemaphores = NULL;
	submit_info[0].pWaitDstStageMask = NULL;
	submit_info[0].commandBufferCount = 1;
	submit_info[0].pCommandBuffers = cmd_bufs;
	submit_info[0].signalSemaphoreCount = 0;
	submit_info[0].pSignalSemaphores = NULL;

	/* Queue the command buffer for execution */
	res = vkQueueSubmit(info.graphics_queue, 1, submit_info, cmdFence);
	assert(res == VK_SUCCESS);

	VkImageSubresource subres = {};
	subres.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	subres.mipLevel = 0;
	subres.arrayLayer = 0;

	VkSubresourceLayout layout;
	void *data;

	/* Get the subresource layout so we know what the row pitch is */
	vkGetImageSubresourceLayout(info.device, mappableImage, &subres, &layout);

	/* Make sure command buffer is finished before mapping */
	do {
		res =
			vkWaitForFences(info.device, 1, &cmdFence, VK_TRUE, FENCE_TIMEOUT);
	} while (res == VK_TIMEOUT);
	assert(res == VK_SUCCESS);

	vkDestroyFence(info.device, cmdFence, NULL);

	res = vkMapMemory(info.device, mappableMemory, 0, mem_reqs.size, 0, &data);
	assert(res == VK_SUCCESS);

	/* Read the ppm file into the mappable image's memory */
	if (!read_ppm(filename.c_str(), texObj.tex_width, texObj.tex_height,
				  layout.rowPitch, cast(byte*)data)) 
	{
		log( "Could not load texture file lunarg.ppm");
		assert(false);
	}

	vkUnmapMemory(info.device, mappableMemory);

	VkCommandBufferBeginInfo cmd_buf_info = {};
	cmd_buf_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
	cmd_buf_info.pNext = NULL;
	cmd_buf_info.flags = 0;
	cmd_buf_info.pInheritanceInfo = NULL;

	res = vkResetCommandBuffer(info.cmd, 0);
	res = vkBeginCommandBuffer(info.cmd, &cmd_buf_info);
	assert(res == VK_SUCCESS);

	if (!needStaging) {
		/* If we can use the linear tiled image as a texture, just do it */
		texObj.image = mappableImage;
		texObj.mem = mappableMemory;
		texObj.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
		set_image_layout(info, texObj.image, VK_IMAGE_ASPECT_COLOR_BIT,
						 VK_IMAGE_LAYOUT_GENERAL, texObj.imageLayout);
		/* No staging resources to free later */
		info.stagingImage = VK_NULL_HANDLE;
		info.stagingMemory = VK_NULL_HANDLE;
	} else {
		/* The mappable image cannot be our texture, so create an optimally
		* tiled image and blit to it */
		image_create_info.tiling = VK_IMAGE_TILING_OPTIMAL;
		image_create_info.usage =
			VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
		image_create_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

		res =
			vkCreateImage(info.device, &image_create_info, NULL, &texObj.image);
		assert(res == VK_SUCCESS);

		vkGetImageMemoryRequirements(info.device, texObj.image, &mem_reqs);

		mem_alloc.allocationSize = mem_reqs.size;

		/* Find memory type - dont specify any mapping requirements */
		pass = memory_type_from_properties(info, mem_reqs.memoryTypeBits,
										   VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
										   &mem_alloc.memoryTypeIndex);
		assert(pass);

		/* allocate memory */
		res = vkAllocateMemory(info.device, &mem_alloc, NULL, &texObj.mem);
		assert(res == VK_SUCCESS);

		/* bind memory */
		res = vkBindImageMemory(info.device, texObj.image, texObj.mem, 0);
		assert(res == VK_SUCCESS);

		/* Since we're going to blit from the mappable image, set its layout to
		* SOURCE_OPTIMAL. Side effect is that this will create info.cmd */
		set_image_layout(info, mappableImage, VK_IMAGE_ASPECT_COLOR_BIT,
						 VK_IMAGE_LAYOUT_GENERAL,
						 VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);

		/* Since we're going to blit to the texture image, set its layout to
		* DESTINATION_OPTIMAL */
		set_image_layout(info, texObj.image, VK_IMAGE_ASPECT_COLOR_BIT,
						 VK_IMAGE_LAYOUT_UNDEFINED,
						 VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

		VkImageCopy copy_region;
		copy_region.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
		copy_region.srcSubresource.mipLevel = 0;
		copy_region.srcSubresource.baseArrayLayer = 0;
		copy_region.srcSubresource.layerCount = 1;
		copy_region.srcOffset.x = 0;
		copy_region.srcOffset.y = 0;
		copy_region.srcOffset.z = 0;
		copy_region.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
		copy_region.dstSubresource.mipLevel = 0;
		copy_region.dstSubresource.baseArrayLayer = 0;
		copy_region.dstSubresource.layerCount = 1;
		copy_region.dstOffset.x = 0;
		copy_region.dstOffset.y = 0;
		copy_region.dstOffset.z = 0;
		copy_region.extent.width = texObj.tex_width;
		copy_region.extent.height = texObj.tex_height;
		copy_region.extent.depth = 1;

		/* Put the copy command into the command buffer */
		vkCmdCopyImage(info.cmd, mappableImage,
					   VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, texObj.image,
					   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy_region);

		/* Set the layout for the texture image from DESTINATION_OPTIMAL to
		* SHADER_READ_ONLY */
		texObj.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
		set_image_layout(info, texObj.image, VK_IMAGE_ASPECT_COLOR_BIT,
						 VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
						 texObj.imageLayout);

		/* Remember staging resources to free later */
		info.stagingImage = mappableImage;
		info.stagingMemory = mappableMemory;
	}

	VkImageViewCreateInfo view_info = {};
	view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
	view_info.pNext = NULL;
	view_info.image = VK_NULL_HANDLE;
	view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
	view_info.format = VK_FORMAT_R8G8B8A8_UNORM;
	view_info.components.r = VK_COMPONENT_SWIZZLE_R;
	view_info.components.g = VK_COMPONENT_SWIZZLE_G;
	view_info.components.b = VK_COMPONENT_SWIZZLE_B;
	view_info.components.a = VK_COMPONENT_SWIZZLE_A;
	view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	view_info.subresourceRange.baseMipLevel = 0;
	view_info.subresourceRange.levelCount = 1;
	view_info.subresourceRange.baseArrayLayer = 0;
	view_info.subresourceRange.layerCount = 1;

	/* create image view */
	view_info.image = texObj.image;
	res = vkCreateImageView(info.device, &view_info, NULL, &texObj.view);
	assert(res == VK_SUCCESS);
	+/
}

void init_texture(ref sample_info info, string textureName,
                  VkImageUsageFlags extraUsages,
                  VkFormatFeatureFlags extraFeatures) 
{
	texture_object texObj;

	/* create image */
	init_image(info, texObj, textureName, extraUsages, extraFeatures);

	/* create sampler */
	init_sampler(info, texObj.sampler);

	info.textures~=texObj;

	/* track a description of the texture */
	info.texture_data.image_info.imageView = info.textures.back().view;
	info.texture_data.image_info.sampler = info.textures.back().sampler;
	info.texture_data.image_info.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
}

void init_viewports(ref sample_info info) 
{
    info.viewport.height = cast(float)info.height;
    info.viewport.width = cast(float)info.width;
    info.viewport.minDepth = cast(float)0.0f;
    info.viewport.maxDepth = cast(float)1.0f;
    info.viewport.x = 0;
    info.viewport.y = 0;
    vkCmdSetViewport(info.cmd, 0, NUM_VIEWPORTS, &info.viewport);
}

void init_scissors(ref sample_info info) {
    info.scissor.extent.width = info.width;
    info.scissor.extent.height = info.height;
    info.scissor.offset.x = 0;
    info.scissor.offset.y = 0;
    vkCmdSetScissor(info.cmd, 0, NUM_SCISSORS, &info.scissor);
}

void init_fence(ref sample_info info, ref VkFence fence) 
{
    VkFenceCreateInfo fenceInfo;
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.pNext = NULL;
    fenceInfo.flags = 0;
    vkCreateFence(info.device, &fenceInfo, NULL, &fence);
}

void init_submit_info(ref sample_info info, ref VkSubmitInfo submit_info,
                      ref VkPipelineStageFlags pipe_stage_flags) 
{
	submit_info.pNext = NULL;
	submit_info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
	submit_info.waitSemaphoreCount = 1;
	submit_info.pWaitSemaphores = &info.imageAcquiredSemaphore;
	submit_info.pWaitDstStageMask = &pipe_stage_flags;
	submit_info.commandBufferCount = 1;
	submit_info.pCommandBuffers = &info.cmd;
	submit_info.signalSemaphoreCount = 0;
	submit_info.pSignalSemaphores = NULL;
}

void init_present_info(ref sample_info info, ref VkPresentInfoKHR present) 
{
    present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present.pNext = NULL;
    present.swapchainCount = 1;
    present.pSwapchains = &info.swap_chain;
    present.pImageIndices = &info.current_buffer;
    present.pWaitSemaphores = NULL;
    present.waitSemaphoreCount = 0;
    present.pResults = NULL;
}

void init_clear_color_and_depth(ref sample_info info,
                                VkClearValue *clear_values) {
									clear_values[0].color.float32[0] = 0.2f;
									clear_values[0].color.float32[1] = 0.2f;
									clear_values[0].color.float32[2] = 0.2f;
									clear_values[0].color.float32[3] = 0.2f;
									clear_values[1].depthStencil.depth = 1.0f;
									clear_values[1].depthStencil.stencil = 0;
								}

void init_render_pass_begin_info(ref sample_info info,
                                 ref VkRenderPassBeginInfo rp_begin) 
{
	rp_begin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
	rp_begin.pNext = NULL;
	rp_begin.renderPass = info.render_pass;
	rp_begin.framebuffer = info.framebuffers[info.current_buffer];
	rp_begin.renderArea.offset.x = 0;
	rp_begin.renderArea.offset.y = 0;
	rp_begin.renderArea.extent.width = info.width;
	rp_begin.renderArea.extent.height = info.height;
	rp_begin.clearValueCount = 0;
	//rp_begin.pClearValues = nullptr;
}

void destroy_pipeline(ref sample_info info) {
    vkDestroyPipeline(info.device, info.pipeline, NULL);
}

void destroy_pipeline_cache(ref sample_info info) {
    vkDestroyPipelineCache(info.device, info.pipelineCache, NULL);
}

void destroy_uniform_buffer(ref sample_info info) {
    vkDestroyBuffer(info.device, info.uniform_data.buf, NULL);
    vkFreeMemory(info.device, info.uniform_data.mem, NULL);
}

void destroy_descriptor_and_pipeline_layouts(ref sample_info info) {
    for (int i = 0; i < NUM_DESCRIPTOR_SETS; i++)
        vkDestroyDescriptorSetLayout(info.device, info.desc_layout[i], NULL);
    vkDestroyPipelineLayout(info.device, info.pipeline_layout, NULL);
}

void destroy_descriptor_pool(ref sample_info info) {
    vkDestroyDescriptorPool(info.device, info.desc_pool, NULL);
}

void destroy_shaders(ref sample_info info) {
    vkDestroyShaderModule(info.device, info.shaderStages[0]._module, NULL);
    vkDestroyShaderModule(info.device, info.shaderStages[1]._module, NULL);
}

void destroy_command_buffer(ref sample_info info) 
{
    VkCommandBuffer[] cmd_bufs = [info.cmd];
    vkFreeCommandBuffers(info.device, info.cmd_pool, 1, cmd_bufs.ptr);
}

void destroy_command_pool(ref sample_info info) {
    vkDestroyCommandPool(info.device, info.cmd_pool, NULL);
}

void destroy_depth_buffer(ref sample_info info) {
    vkDestroyImageView(info.device, info.depth.view, NULL);
    vkDestroyImage(info.device, info.depth.image, NULL);
    vkFreeMemory(info.device, info.depth.mem, NULL);
}

void destroy_vertex_buffer(ref sample_info info) {
    vkDestroyBuffer(info.device, info.vertex_buffer.buf, NULL);
    vkFreeMemory(info.device, info.vertex_buffer.mem, NULL);
}

void destroy_swap_chain(ref sample_info info) {
    for (uint i = 0; i < info.swapchainImageCount; i++) {
        vkDestroyImageView(info.device, info.buffers[i].view, NULL);
    }
    vkDestroySwapchainKHR(info.device, info.swap_chain, NULL);
}

void destroy_framebuffers(ref sample_info info) {
    for (uint i = 0; i < info.swapchainImageCount; i++) {
        vkDestroyFramebuffer(info.device, info.framebuffers[i], NULL);
    }
}

void destroy_renderpass(ref sample_info info) {
    vkDestroyRenderPass(info.device, info.render_pass, NULL);
}

void destroy_device(ref sample_info info) {
    vkDestroyDevice(info.device, NULL);
}

void destroy_instance(ref sample_info info) {
    vkDestroyInstance(info.inst, NULL);
}

void destroy_textures(ref sample_info info) {
    for (size_t i = 0; i < info.textures.length; i++) {
        vkDestroySampler(info.device, info.textures[i].sampler, NULL);
        vkDestroyImageView(info.device, info.textures[i].view, NULL);
        vkDestroyImage(info.device, info.textures[i].image, NULL);
        vkFreeMemory(info.device, info.textures[i].mem, NULL);
    }
    if (info.stagingImage) {
        vkDestroyImage(info.device, info.stagingImage, NULL);
    }
    if (info.stagingMemory) {
        vkFreeMemory(info.device, info.stagingMemory, NULL);
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

	log("DVulkanDerelict.load.");
	DVulkanDerelict.load();
	DVulkanDerelict.loadInitializationFunctions();
    
    sample_info info;
    auto sample_title = "Draw Cube";
    const bool depthPresent = true;

    //process_command_line_args(info, argc, argv);
    init_global_layer_properties(info);
    init_instance_extension_names(info);
    init_device_extension_names(info);
    init_instance(info, sample_title);
loadInstanceFunctions(info.inst);

    init_enumerate_device(info);
    init_window_size(info, 500, 500);
    init_connection(info);
    //init_window(info);
	info.connection=GetModuleHandle(null);
	info.window=glfw.get_hwnd();
    init_swapchain_extension(info);
    init_device(info);

    init_command_pool(info);
    init_command_buffer(info);
    execute_begin_command_buffer(info);
    init_device_queue(info);
    init_swap_chain(info);
    init_depth_buffer(info);
    init_uniform_buffer(info);
    init_descriptor_and_pipeline_layouts(info, false);
    init_renderpass(info, depthPresent);
    init_shaders(info, "cube-vert.spv", "cube-frag.spv");
    init_framebuffers(info, depthPresent);
	/*
    init_vertex_buffer(info, g_vb_solid_face_colors_Data,
                       sizeof(g_vb_solid_face_colors_Data),
                       sizeof(g_vb_solid_face_colors_Data[0]), false);
	*/
    init_descriptor_pool(info, false);
    init_descriptor_set(info, false);
    init_pipeline_cache(info);
    init_pipeline(info, depthPresent);

    /* VULKAN_KEY_START */

    VkClearValue[2] clear_values;
    clear_values[0].color.float32[0] = 0.2f;
    clear_values[0].color.float32[1] = 0.2f;
    clear_values[0].color.float32[2] = 0.2f;
    clear_values[0].color.float32[3] = 0.2f;
    clear_values[1].depthStencil.depth = 1.0f;
    clear_values[1].depthStencil.stencil = 0;

    VkSemaphore imageAcquiredSemaphore;
    VkSemaphoreCreateInfo imageAcquiredSemaphoreCreateInfo;
    imageAcquiredSemaphoreCreateInfo.sType =
        VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    imageAcquiredSemaphoreCreateInfo.pNext = NULL;
    imageAcquiredSemaphoreCreateInfo.flags = 0;

    auto res = vkCreateSemaphore(info.device, &imageAcquiredSemaphoreCreateInfo,
                            NULL, &imageAcquiredSemaphore);
    assert(res == VK_SUCCESS);

    // Get the index of the next available swapchain image:
    res = vkAcquireNextImageKHR(info.device, info.swap_chain, ulong.max,
                                imageAcquiredSemaphore, VkFence.init,
                                &info.current_buffer);
    // TODO: Deal with the VK_SUBOPTIMAL_KHR and VK_ERROR_OUT_OF_DATE_KHR
    // return codes
    assert(res == VK_SUCCESS);

    set_image_layout(info, info.buffers[info.current_buffer].image,
                     VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_LAYOUT_UNDEFINED,
                     VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);

    VkRenderPassBeginInfo rp_begin;
    rp_begin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rp_begin.pNext = NULL;
    rp_begin.renderPass = info.render_pass;
    rp_begin.framebuffer = info.framebuffers[info.current_buffer];
    rp_begin.renderArea.offset.x = 0;
    rp_begin.renderArea.offset.y = 0;
    rp_begin.renderArea.extent.width = info.width;
    rp_begin.renderArea.extent.height = info.height;
    rp_begin.clearValueCount = 2;
    rp_begin.pClearValues = clear_values.ptr;

    vkCmdBeginRenderPass(info.cmd, &rp_begin, VK_SUBPASS_CONTENTS_INLINE);

    vkCmdBindPipeline(info.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, info.pipeline);
    vkCmdBindDescriptorSets(info.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                            info.pipeline_layout, 0, NUM_DESCRIPTOR_SETS,
                            info.desc_set.ptr, 0, NULL);

    const VkDeviceSize[1] offsets;
    vkCmdBindVertexBuffers(info.cmd, 0, 1, &info.vertex_buffer.buf, offsets.ptr);

    init_viewports(info);
    init_scissors(info);

    vkCmdDraw(info.cmd, 12 * 3, 1, 0, 0);
    vkCmdEndRenderPass(info.cmd);
    res = vkEndCommandBuffer(info.cmd);
    const VkCommandBuffer[] cmd_bufs = [info.cmd];
    VkFenceCreateInfo fenceInfo;
    VkFence drawFence;
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.pNext = NULL;
    fenceInfo.flags = 0;
    vkCreateFence(info.device, &fenceInfo, NULL, &drawFence);

    VkPipelineStageFlags pipe_stage_flags =
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo[1] submit_info;
    submit_info[0].pNext = NULL;
    submit_info[0].sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit_info[0].waitSemaphoreCount = 1;
    submit_info[0].pWaitSemaphores = &imageAcquiredSemaphore;
    submit_info[0].pWaitDstStageMask = &pipe_stage_flags;
    submit_info[0].commandBufferCount = 1;
    submit_info[0].pCommandBuffers = cmd_bufs.ptr;
    submit_info[0].signalSemaphoreCount = 0;
    submit_info[0].pSignalSemaphores = NULL;

    /* Queue the command buffer for execution */
    res = vkQueueSubmit(info.graphics_queue, 1, submit_info.ptr, drawFence);
    assert(res == VK_SUCCESS);

    /* Now present the image in the window */

    VkPresentInfoKHR present;
    present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present.pNext = NULL;
    present.swapchainCount = 1;
    present.pSwapchains = &info.swap_chain;
    present.pImageIndices = &info.current_buffer;
    present.pWaitSemaphores = NULL;
    present.waitSemaphoreCount = 0;
    present.pResults = NULL;

    /* Make sure command buffer is finished before presenting */
    do {
        res =
            vkWaitForFences(info.device, 1, &drawFence, VK_TRUE, FENCE_TIMEOUT);
    } while (res == VK_TIMEOUT);

    assert(res == VK_SUCCESS);
    res = vkQueuePresentKHR(info.present_queue, &present);
    assert(res == VK_SUCCESS);

    /* VULKAN_KEY_END */
	/*
    if (info.save_images)
        write_ppm(info, "drawcube");
	*/

	while(glfw.newFrame()){
		//
	}

    vkDestroySemaphore(info.device, imageAcquiredSemaphore, NULL);
    vkDestroyFence(info.device, drawFence, NULL);
    destroy_pipeline(info);
    destroy_pipeline_cache(info);
    destroy_descriptor_pool(info);
    destroy_vertex_buffer(info);
    destroy_framebuffers(info);
    destroy_shaders(info);
    destroy_renderpass(info);
    destroy_descriptor_and_pipeline_layouts(info);
    destroy_uniform_buffer(info);
    destroy_depth_buffer(info);
    destroy_swap_chain(info);
    destroy_command_buffer(info);
    destroy_command_pool(info);
    destroy_device(info);
    //destroy_window(info);
    destroy_instance(info);

}
