version = DVulkanAllExtensions;
version = DVulkanGlobalEnums;
import cube;
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
import std.string;
import core.sys.windows.windows;
import core.stdc.string;
import gfm.math;


enum VK_KHR_WIN32_SURFACE_EXTENSION_NAME = "VK_KHR_win32_surface";


extern(C) VkBool32 MyDebugReportCallback(
										 VkDebugReportFlagsEXT       flags,
										 VkDebugReportObjectTypeEXT  objectType,
										 ulong                    object,
										 uint                      location,
										 int                     messageCode,
										 const char*                 pLayerPrefix,
										 const char*                 pMessage,
										 void*                       pUserData)
{
	auto msg=fromStringz(pMessage);
	error(msg);
    return VK_FALSE;
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

	bool initialize(int w, int h)
	{
		glfwInit();
		const window_width  = w;
		const window_height = h;
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
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

	void swapBuffers()
	{
		glfwSwapBuffers(window);
	}
}


class InstanceManager
{
	VkInstance m_inst;
	VkDebugReportCallbackEXT m_callback;
	//PFN_vkCreateDebugReportCallbackEXT g_vkCreateDebugReportCallbackEXT;
	//PFN_vkDebugReportMessageEXT g_vkDebugReportMessageEXT;
	//PFN_vkDestroyDebugReportCallbackEXT g_vkDestroyDebugReportCallbackEXT;
	VkDebugReportCallbackEXT[] m_debug_report_callbacks;

	this(VkInstance inst)
	{
		m_inst=inst;
		loadInstanceFunctions(inst);
	}

public:
	~this()
	{
		//debug
		foreach(cb; m_debug_report_callbacks)
		{
			vkDestroyDebugReportCallbackEXT(m_inst, cb, null);
		}
		vkDestroyInstance(m_inst, null);
	}

	VkInstance get(){ return m_inst; }

	bool setupDebugCallback(PFN_vkDebugReportCallbackEXT dbgFunc)
	{
		VkDebugReportCallbackCreateInfoEXT create_info;
		create_info.flags =
			VK_DEBUG_REPORT_ERROR_BIT_EXT 
			| VK_DEBUG_REPORT_WARNING_BIT_EXT
			| VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT
			//| VK_DEBUG_REPORT_DEBUG_BIT_EXT 
			//| VK_DEBUG_REPORT_INFORMATION_BIT_EXT 
			;
		create_info.pfnCallback = dbgFunc;
		create_info.pUserData = null;

		VkDebugReportCallbackEXT debug_report_callback;
		auto res = vkCreateDebugReportCallbackEXT(m_inst, &create_info, null,
												  &debug_report_callback);
		switch (res) {
			case VK_SUCCESS:
				log( "Successfully created debug report callback object");
				m_debug_report_callbacks~=debug_report_callback;
				return true;

			case VK_ERROR_OUT_OF_HOST_MEMORY:
				log("dbgCreateDebugReportCallback: out of host memory pointer");
				//return VkResult.VK_ERROR_INITIALIZATION_FAILED;
				break;

			default:
				log( "dbgCreateDebugReportCallback: unknown failure");
				//return VkResult.VK_ERROR_INITIALIZATION_FAILED;
				break;
		}
		return false;
	}

	static InstanceManager create(string app_name, string engine_name)
	{
		string[] instance_layer_names;
		string[] instance_extension_names;
		instance_extension_names~=VK_KHR_SURFACE_EXTENSION_NAME;
		instance_extension_names~=VK_KHR_WIN32_SURFACE_EXTENSION_NAME;
		//debug
		{
			// Enable validation layers in debug builds 
			// to detect validation errors
			instance_layer_names~="VK_LAYER_LUNARG_standard_validation";
			// Enable debug report extension in debug builds 
			// to be able to consume validation errors 
			instance_extension_names~="VK_EXT_debug_report";
		}

		VkApplicationInfo app_info;
		app_info.pApplicationName = app_name.ptr;
		app_info.applicationVersion = 1;
		app_info.pEngineName = engine_name.ptr;
		app_info.engineVersion = 1;
		app_info.apiVersion = VK_MAKE_VERSION(1, 0, 2);

		VkInstanceCreateInfo inst_info;
		inst_info.pApplicationInfo = &app_info;
		// layers
		inst_info.enabledLayerCount = instance_layer_names.length;
		inst_info.ppEnabledLayerNames = instance_layer_names.map!("a.ptr").array.ptr;
		// extensions
		inst_info.enabledExtensionCount = instance_extension_names.length;
		inst_info.ppEnabledExtensionNames = instance_extension_names.map!("a.ptr").array.ptr;

		VkInstance inst;
		VkResult res = vkCreateInstance(&inst_info, null, &inst);
		if (res != VK_SUCCESS) {
			return null;
		}
		auto instanceManager = new InstanceManager(inst);

		//debug
		{
			if (!instanceManager.setupDebugCallback(&MyDebugReportCallback)) {
				return null;
			}
		}

		return instanceManager;
	}
};


class GpuManager
{
	VkPhysicalDevice m_gpu;
	VkQueueFamilyProperties[] m_queue_props;
	VkPhysicalDeviceMemoryProperties m_memory_properties;
	VkPhysicalDeviceProperties m_gpu_props;

	uint m_graphics_queue_family_index=uint.max;
	uint m_present_queue_family_index=uint.max;

	VkFormat m_format = VK_FORMAT_UNDEFINED;

	this(VkPhysicalDevice gpu)
	{
		m_gpu=gpu;
	}
public:

	static GpuManager[] enumerate_gpu(VkInstance inst)
	{
		GpuManager[] gpus;
		uint pdevice_count = 0;
		VkResult res = vkEnumeratePhysicalDevices(inst, &pdevice_count, null);
		if (pdevice_count > 0) {
			auto pdevices=new VkPhysicalDevice[pdevice_count];
			res = vkEnumeratePhysicalDevices(inst, &pdevice_count, pdevices.ptr);
			if (res == VK_SUCCESS) {
				foreach (pdevice; pdevices)
				{
					auto gpuManager = new GpuManager(pdevice);
					if (!gpuManager.initialize()) {
						break;
					}
					gpus~=gpuManager;
				}
			}
		}
		return gpus;
	}

	VkPhysicalDevice get() { return m_gpu; }
	VkFormat getPrimaryFormat() { return m_format; }
	uint get_graphics_queue_family_index()const
	{
		return m_graphics_queue_family_index;
	}
	uint get_present_queue_family_index()const
	{
		return m_present_queue_family_index;
	}
	bool memory_type_from_properties(uint typeBits, VkFlags requirements_mask, uint *typeIndex)const
	{
		// Search memtypes to find first index with those properties
		for (uint i = 0; i < m_memory_properties.memoryTypeCount; i++) {
			if ((typeBits & 1) == 1) {
				// Type is available, does it match user properties?
				if ((m_memory_properties.memoryTypes[i].propertyFlags &
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

	bool initialize()
	{
		uint queue_family_count;
		vkGetPhysicalDeviceQueueFamilyProperties(m_gpu,
												 &queue_family_count, null);
		if (queue_family_count == 0) {
			return false;
		}

		m_queue_props.length=queue_family_count;
		vkGetPhysicalDeviceQueueFamilyProperties(
												 m_gpu, &queue_family_count, m_queue_props.ptr);
		if (queue_family_count != m_queue_props.length) {
			return false;
		}

		// This is as good a place as any to do this
		vkGetPhysicalDeviceMemoryProperties(m_gpu, &m_memory_properties);
		vkGetPhysicalDeviceProperties(m_gpu, &m_gpu_props);
		return true;
	}

	bool prepare(VkSurfaceKHR surface)
	{
		// Iterate over each queue to learn whether it supports presenting:
		auto pSupportsPresent=new VkBool32[m_queue_props.length];
		for (uint i = 0; i < pSupportsPresent.length; i++) {
			vkGetPhysicalDeviceSurfaceSupportKHR(m_gpu, i, surface,
												 &pSupportsPresent[i]);
		}

		// Search for a graphics and a present queue in the array of queue
		// families, try to find one that supports both
		m_graphics_queue_family_index = uint.max;
		m_present_queue_family_index = uint.max;
		for (uint i = 0; i < m_queue_props.length; ++i) {
			if ((m_queue_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
				if (m_graphics_queue_family_index == uint.max) {
					m_graphics_queue_family_index = i;
				}

				if (pSupportsPresent[i] == VK_TRUE) {
					m_graphics_queue_family_index = i;
					m_present_queue_family_index = i;
					break;
				}
			}
		}

		if (m_present_queue_family_index == uint.max) {
			// If didn't find a queue that supports both graphics and present, then
			// find a separate present queue.
			for (size_t i = 0; i < m_queue_props.length; ++i)
				if (pSupportsPresent[i] == VK_TRUE) {
					m_present_queue_family_index = i;
					break;
				}
		}

		// Generate error if could not find queues that support graphics
		// and present
		if (m_graphics_queue_family_index == uint.max ||
			m_present_queue_family_index == uint.max) {
				//throw "Could not find a queues for both graphics and present";
				return false;
			}

		// Get the list of VkFormats that are supported:
		uint formatCount;
		auto res = vkGetPhysicalDeviceSurfaceFormatsKHR(m_gpu, surface,
														&formatCount, null);
		if (res != VK_SUCCESS) {
			return false;
		}
		if (formatCount == 0) {
			return false;
		}
		auto surfFormats=new VkSurfaceFormatKHR[formatCount];
		res = vkGetPhysicalDeviceSurfaceFormatsKHR(m_gpu, surface,
												   &formatCount, surfFormats.ptr);
		if (res != VK_SUCCESS) {
			return false;
		}

		if (formatCount == 1 && surfFormats[0].format == VK_FORMAT_UNDEFINED) {
			// If the format list includes just one entry of VK_FORMAT_UNDEFINED,
			// the surface has no preferred format.  Otherwise, at least one
			// supported format will be returned.
			m_format = VK_FORMAT_B8G8R8A8_UNORM;
			return true;
		}
		else {
			m_format = surfFormats[0].format;
		}

		return true;
	}
};


class DeviceManager
{
	InstanceManager m_inst;
	string[] m_device_extension_names;
	string[] m_device_layer_names;
	VkDevice m_device;

public:
	this(InstanceManager inst)
	{
		m_inst=inst;
		m_device_extension_names~=VK_KHR_SWAPCHAIN_EXTENSION_NAME;
		//debug
		{
			// Enable validation layers in debug builds to detect validation errors
			m_device_layer_names~="VK_LAYER_LUNARG_standard_validation";
		}
	}

	~this()
	{
		vkDestroyDevice(m_device, null);
	}

	VkDevice get() { return m_device; }

	bool create(GpuManager gpu)
	{
		int graphics_queue_family_index = gpu.get_graphics_queue_family_index();
		if (graphics_queue_family_index < 0) {
			return false;
		}

		VkDeviceQueueCreateInfo queue_info;
		auto queue_priorities = [ 0.0f ];
		queue_info.queueCount = queue_priorities.length;
		queue_info.pQueuePriorities = queue_priorities.ptr;
		queue_info.queueFamilyIndex = graphics_queue_family_index;

		VkDeviceCreateInfo device_info;
		device_info.queueCreateInfoCount = 1;
		device_info.pQueueCreateInfos = &queue_info;

		device_info.enabledExtensionCount = m_device_extension_names.length;
		device_info.ppEnabledExtensionNames = m_device_extension_names.map!("a.ptr").array.ptr;

		device_info.enabledLayerCount = m_device_layer_names.length;
		device_info.ppEnabledLayerNames = m_device_layer_names.map!("a.ptr").array.ptr;

		auto res = vkCreateDevice(gpu.get(), &device_info, null, &m_device);
		if (res != VK_SUCCESS) {
			return false;
		}

		return true;
	}
};


class SurfaceManager
{
	InstanceManager m_inst;
	VkSurfaceKHR m_surface;

	VkSurfaceCapabilitiesKHR m_surfCapabilities;
	VkPresentModeKHR[] m_presentModes;

	alias PFN_vkCreateWin32SurfaceKHR
		= extern(C) VkResult function(VkInstance instance,
				const(VkWin32SurfaceCreateInfoKHR)* pCreateInfo
					, const(VkAllocationCallbacks)* pAllocator
						,VkSurfaceKHR* pSurface);
	PFN_vkCreateWin32SurfaceKHR vkCreateWin32SurfaceKHR;

public:
	this(InstanceManager inst)
	{
		m_inst=inst;

		auto p=vkGetInstanceProcAddr(inst.get(), "vkCreateWin32SurfaceKHR");
		vkCreateWin32SurfaceKHR
			= cast(PFN_vkCreateWin32SurfaceKHR) p;
		enforce(vkCreateWin32SurfaceKHR, "vkGetInstanceProcAddr vkCreateWin32SurfaceKHR");
	}

	~this()
	{
		vkDestroySurfaceKHR(m_inst.get(), m_surface, null);
	}

	VkSurfaceKHR get()const { return m_surface; }

	struct VkWin32SurfaceCreateInfoKHR
	{
		VkStructureType sType = VkStructureType.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
		const(void)* pNext;
		VkFlags flags;
		HINSTANCE hinstance;
		HWND hwnd;
	};
	bool create(HINSTANCE hInstance, HWND hWnd)
	{
		VkWin32SurfaceCreateInfoKHR createInfo;
		createInfo.hinstance = hInstance;
		createInfo.hwnd = hWnd;
		auto res = vkCreateWin32SurfaceKHR(m_inst.get(), &createInfo,
										   null, &m_surface);
		return true;
	}

	bool getCapabilityFor(VkPhysicalDevice gpu)
	{
		auto res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, m_surface,
															 &m_surfCapabilities);
		if (res != VK_SUCCESS) {
			return false;
		}

		uint presentModeCount;
		res = vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, m_surface,
														&presentModeCount, null);
		if (res != VK_SUCCESS) {
			return false;
		}
		if (presentModeCount == 0) {
			return false;
		}

		m_presentModes.length=presentModeCount;
		res = vkGetPhysicalDeviceSurfacePresentModesKHR(
														gpu, m_surface, &presentModeCount, m_presentModes.ptr);
		if (res != VK_SUCCESS) {
			return false;
		}

		return true;
	}

	VkPresentModeKHR getSwapchainPresentMode()const
	{
		// If mailbox mode is available, use it, as is the lowest-latency non-
		// tearing mode.  If not, try IMMEDIATE which will usually be available,
		// and is fastest (though it tears).  If not, fall back to FIFO which is
		// always available.
		VkPresentModeKHR swapchainPresentMode = VK_PRESENT_MODE_FIFO_KHR;
		foreach (mode; m_presentModes) {
			if (mode == VK_PRESENT_MODE_MAILBOX_KHR) {
				swapchainPresentMode = VK_PRESENT_MODE_MAILBOX_KHR;
				break;
			}
			if ((swapchainPresentMode != VK_PRESENT_MODE_MAILBOX_KHR) &&
				(mode == VK_PRESENT_MODE_IMMEDIATE_KHR)) {
					swapchainPresentMode = VK_PRESENT_MODE_IMMEDIATE_KHR;
				}
		}

		return swapchainPresentMode;
	}

	uint getDesiredNumberOfSwapchainImages()const
	{
		// Determine the number of VkImage's to use in the swap chain.
		// We need to acquire only 1 presentable image at at time.
		// Asking for minImageCount images ensures that we can acquire
		// 1 presentable image as long as we present it before attempting
		// to acquire another.
		return m_surfCapabilities.minImageCount;
	}

	VkSurfaceTransformFlagBitsKHR getPreTransform()const
	{
		if (m_surfCapabilities.supportedTransforms &
			VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR) {
				return VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
			}
		else {
			return m_surfCapabilities.currentTransform;
		}
	}

	VkExtent2D getExtent(int w, int h)const
	{
		// width and height are either both 0xFFFFFFFF, or both not 0xFFFFFFFF.
		if (m_surfCapabilities.currentExtent.width != 0xFFFFFFFF) {
			return m_surfCapabilities.currentExtent;
		}

		VkExtent2D swapchainExtent;
		// If the surface size is undefined, the size is set to
		// the size of the images requested.
		swapchainExtent.width = w;
		swapchainExtent.height = h;
		if (swapchainExtent.width < m_surfCapabilities.minImageExtent.width) {
			swapchainExtent.width = m_surfCapabilities.minImageExtent.width;
		}
		else if (swapchainExtent.width >
				 m_surfCapabilities.maxImageExtent.width) {
					 swapchainExtent.width = m_surfCapabilities.maxImageExtent.width;
				 }

		if (swapchainExtent.height < m_surfCapabilities.minImageExtent.height) {
			swapchainExtent.height = m_surfCapabilities.minImageExtent.height;
		}
		else if (swapchainExtent.height >
				 m_surfCapabilities.maxImageExtent.height) {
					 swapchainExtent.height = m_surfCapabilities.maxImageExtent.height;
				 }
		return swapchainExtent;
	}
};


class FramebufferResource
{
	DeviceManager m_device;

	VkRenderPass m_renderpass;
	VkFramebuffer m_framebuffer;

	VkAttachmentReference m_color_reference;
	VkAttachmentReference m_depth_reference;
	VkSubpassDescription[] m_subpasses;
	VkAttachmentDescription[] m_attachments;
	VkImageView[] m_views;

public:
	this(DeviceManager device)
	{
		m_device=device;
	}

	~this()
	{
		vkDestroyFramebuffer(m_device.get(), m_framebuffer, null);
		vkDestroyRenderPass(m_device.get(), m_renderpass, null);
	}

	VkRenderPass getRenderPass()const { return m_renderpass; }
	VkFramebuffer getFramebuffer()const { return m_framebuffer; }

	bool create(int w, int h)
	{
		// renderpass
		VkRenderPassCreateInfo rp_info;
		rp_info.attachmentCount = m_attachments.length;
		rp_info.pAttachments = m_attachments.ptr;
		rp_info.subpassCount = m_subpasses.length;
		rp_info.pSubpasses = m_subpasses.ptr;
		rp_info.dependencyCount = 0;
		auto res = vkCreateRenderPass(m_device.get(), &rp_info, null, &m_renderpass);
		if (res != VK_SUCCESS) {
			return false;
		}

		// framebuffer
		VkFramebufferCreateInfo fb_info;
		fb_info.renderPass = m_renderpass;
		fb_info.attachmentCount = m_views.length;
		fb_info.pAttachments = m_views.ptr;
		fb_info.width = w;
		fb_info.height = h;
		fb_info.layers = 1;
		res = vkCreateFramebuffer(m_device.get(), &fb_info, null,
								  &m_framebuffer);
		if (res != VK_SUCCESS) {
			return false;
		}

		return true;
	}

	void attachColor(VkImageView view, VkFormat format, VkSampleCountFlagBits samples
					 , bool clear=true)
	{
		m_views~=view;
		m_attachments~=VkAttachmentDescription();
		m_attachments[$-1].format = format;
		m_attachments[$-1].samples = samples;
		m_attachments[$-1].loadOp = clear ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		m_attachments[$-1].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		m_attachments[$-1].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		m_attachments[$-1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		m_attachments[$-1].initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
		m_attachments[$-1].finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
		m_attachments[$-1].flags = 0;
	}

	void attachDepth(VkImageView view, VkFormat format, VkSampleCountFlagBits samples
					 , bool clear = true)
	{
		m_views~=view;
		m_attachments~=VkAttachmentDescription();
		m_attachments[$-1].format = format;
		m_attachments[$-1].samples = samples;
		m_attachments[$-1].loadOp = clear ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		m_attachments[$-1].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		m_attachments[$-1].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_LOAD;
		m_attachments[$-1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_STORE;
		m_attachments[$-1].initialLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		m_attachments[$-1].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		m_attachments[$-1].flags = 0;
	}

	void pushSubpass(int colorIndex, int depthIndex)
	{
		m_color_reference.attachment = colorIndex;
		m_color_reference.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

		m_depth_reference.attachment = depthIndex;
		m_depth_reference.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

		m_subpasses~=VkSubpassDescription();
		m_subpasses[$-1].pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
		m_subpasses[$-1].flags = 0;
		m_subpasses[$-1].inputAttachmentCount = 0;
		m_subpasses[$-1].colorAttachmentCount = 1;
		m_subpasses[$-1].pColorAttachments = &m_color_reference;
		m_subpasses[$-1].pDepthStencilAttachment = &m_depth_reference;
		m_subpasses[$-1].preserveAttachmentCount = 0;
	}
};


class DeviceMemoryResource
{
	DeviceManager m_device;
	VkDeviceMemory m_mem;
	ulong m_size = 0;

public:
	this(DeviceManager device)
	{
		m_device=device;
	}

	~this()
	{
		vkFreeMemory(m_device.get(), m_mem, null);
	}

	VkDeviceMemory get()const {
		return m_mem;
	}

	bool allocate(GpuManager gpu
				  , VkMemoryRequirements mem_reqs
					  , VkFlags flags)
	{
		VkMemoryAllocateInfo alloc_info;
		alloc_info.memoryTypeIndex = 0;
		alloc_info.allocationSize = mem_reqs.size;
		if (!gpu.memory_type_from_properties(mem_reqs.memoryTypeBits
											  , flags
											  , &alloc_info.memoryTypeIndex)) {
												  //assert(pass && "No mappable, coherent memory");
												  return false;
											  }
		auto res = vkAllocateMemory(m_device.get(), &alloc_info, null, &m_mem);
		if (res != VK_SUCCESS) {
			return false;
		}
		m_size = mem_reqs.size;
		return true;
	}

	bool map(alias mapCallback)()
	{
		byte *pData;
		auto res = vkMapMemory(m_device.get(), m_mem, 0, m_size, 0
							   , cast(void **)&pData);
		if (res != VK_SUCCESS) {
			return false;
		}

		mapCallback(pData, cast(uint)m_size);

		vkUnmapMemory(m_device.get(), m_mem);

		return true;
	}
};


class BufferResource
{
	DeviceManager m_device;

	VkBuffer m_buf;
	VkMemoryRequirements m_mem_reqs;
	VkDescriptorBufferInfo m_buffer_info;

public:
	this(DeviceManager device)
	{
		m_device=device;
	}

	~this()
	{
		vkDestroyBuffer(m_device.get(), m_buf, null);
	}

	VkBuffer getBuffer()const { return m_buf; }
	VkDescriptorBufferInfo getDescInfo()const 
	{ 
		return m_buffer_info; 
	}
	VkMemoryRequirements getMemoryRequirements()const
	{
		return m_mem_reqs;
	}

	bool create(GpuManager gpu
				, VkBufferUsageFlags usage, uint dataSize)
	{
		// buffer
		VkBufferCreateInfo buf_info;
		buf_info.usage = usage;
		buf_info.size = dataSize;
		buf_info.queueFamilyIndexCount = 0;
		buf_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
		auto res = vkCreateBuffer(m_device.get(), &buf_info, null
								  , &m_buf);
		if (res != VK_SUCCESS) {
			return false;
		}

		vkGetBufferMemoryRequirements(m_device.get(), m_buf, &m_mem_reqs);
		// desc
		m_buffer_info.buffer = m_buf;
		m_buffer_info.range = m_mem_reqs.size;
		m_buffer_info.offset = 0;

		return true;
	}

	bool bind(VkDeviceMemory mem)
	{
		auto res = vkBindBufferMemory(m_device.get(), m_buf, mem, 0);
		if (res != VK_SUCCESS) {
			return false;
		}
		return true;
	}
};


class VertexbufferDesc
{
	VkVertexInputBindingDescription m_vi_binding;
	VkVertexInputAttributeDescription[] m_vi_attribs;
public:
	this()
	{
		m_vi_binding.binding = 0;
		m_vi_binding.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;
	}
	ref VkVertexInputBindingDescription getBindingDesc() {
		return m_vi_binding;
	}
	VkVertexInputAttributeDescription* getAttribs()
	{
		return m_vi_attribs.ptr;
	}
	void pushAttrib(VkFormat format= VK_FORMAT_R32G32B32A32_SFLOAT, uint offset=16)
	{
		uint location=m_vi_attribs.length;
		m_vi_attribs~=VkVertexInputAttributeDescription();
		m_vi_attribs[$-1].binding = 0;
		m_vi_attribs[$-1].location = location;
		m_vi_attribs[$-1].format = format;
		m_vi_attribs[$-1].offset = m_vi_binding.stride;
		m_vi_binding.stride += 16;
	}
};


class DepthbufferResource
{
	DeviceManager m_device;

	VkSampleCountFlagBits m_depth_samples = VK_SAMPLE_COUNT_1_BIT;
	VkFormat m_depth_format = VK_FORMAT_D16_UNORM;

	VkImage m_image;
	VkMemoryRequirements m_mem_reqs;

	VkImageView m_view;
	VkImageViewCreateInfo m_view_info;

public:
	this(DeviceManager device)
	{
		m_device=device;
	}

	~this()
	{
		vkDestroyImageView(m_device.get(), m_view, null);
		vkDestroyImage(m_device.get(), m_image, null);
	}

	VkSampleCountFlagBits getSamples()const { return m_depth_samples; }
	VkFormat getFormat()const { return m_depth_format; }
	VkImageView getView()const { return m_view; }
	VkImage getImage()const { return m_image; }
	VkImageAspectFlags getAspect()const { return m_view_info.subresourceRange.aspectMask; }
	VkMemoryRequirements getMemoryRquirements()const { return m_mem_reqs; }

	bool create(GpuManager gpu, int w, int h)
	{
		// image
		VkFormatProperties props;
		vkGetPhysicalDeviceFormatProperties(gpu.get(), m_depth_format, &props);

		VkImageCreateInfo image_info;
		if (props.linearTilingFeatures &
			VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
				image_info.tiling = VK_IMAGE_TILING_LINEAR;
			}
		else if (props.optimalTilingFeatures &
				 VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
					 image_info.tiling = VK_IMAGE_TILING_OPTIMAL;
				 }
		else {
			/* Try other depth formats? */
			//std::cout << "depth_format " << depth_format << " Unsupported.\n";
			return false;
		}
		image_info.imageType = VK_IMAGE_TYPE_2D;
		image_info.format = m_depth_format;
		image_info.extent.width = w;
		image_info.extent.height = h;
		image_info.extent.depth = 1;
		image_info.mipLevels = 1;
		image_info.arrayLayers = 1;
		image_info.samples = m_depth_samples;
		image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		image_info.queueFamilyIndexCount = 0;
		image_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
		image_info.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
		image_info.flags = 0;
		auto res = vkCreateImage(m_device.get(), &image_info, null, &m_image);
		if (res != VK_SUCCESS) {
			return false;
		}
		// mem
		vkGetImageMemoryRequirements(m_device.get(), m_image, &m_mem_reqs);
		return true;
	}

	bool bind(VkDeviceMemory mem)
	{
		auto res = vkBindImageMemory(m_device.get(), m_image, mem, 0);
		if (res != VK_SUCCESS) {
			return false;
		}
		return true;
	}

	// must call after vkBindImageMemory
	bool createView()
	{
		m_view_info.format = m_depth_format;
		m_view_info.components.r = VK_COMPONENT_SWIZZLE_R;
		m_view_info.components.g = VK_COMPONENT_SWIZZLE_G;
		m_view_info.components.b = VK_COMPONENT_SWIZZLE_B;
		m_view_info.components.a = VK_COMPONENT_SWIZZLE_A;
		m_view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
		m_view_info.subresourceRange.baseMipLevel = 0;
		m_view_info.subresourceRange.levelCount = 1;
		m_view_info.subresourceRange.baseArrayLayer = 0;
		m_view_info.subresourceRange.layerCount = 1;
		m_view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
		m_view_info.flags = 0;
		m_view_info.image = m_image;
		if (m_depth_format == VK_FORMAT_D16_UNORM_S8_UINT ||
			m_depth_format == VK_FORMAT_D24_UNORM_S8_UINT ||
			m_depth_format == VK_FORMAT_D32_SFLOAT_S8_UINT) {
				m_view_info.subresourceRange.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT;
			}

		auto res = vkCreateImageView(m_device.get(), &m_view_info, null, &m_view);
		if (res != VK_SUCCESS)
		{
			return false;
		}

		return true;
	}
};


class SwapchainResource
{
	DeviceManager m_device;
	VkSwapchainKHR m_swapchain;

	struct swap_chain_buffer
	{
		VkImage image;
		VkImageView view;

		void destroy(VkDevice device)
		{
			vkDestroyImageView(device, view, null);
		}
	};
	swap_chain_buffer[] m_buffers;

	VkSemaphoreCreateInfo m_imageAcquiredSemaphoreCreateInfo;
	VkSemaphore m_imageAcquiredSemaphore;
	uint m_current_buffer = 0;

	uint m_present_queue_family_index = 0;
	VkQueue m_present_queue;

public:
	this(DeviceManager device)
	{
		m_device=device;
	}

	~this()
	{
		vkDestroySemaphore(m_device.get(), m_imageAcquiredSemaphore, null);
		foreach(ref b; m_buffers)
		{
			b.destroy(m_device.get());
		}
		m_buffers.length=0;
		vkDestroySwapchainKHR(m_device.get(), m_swapchain, null);
	}

	uint getImageCount()const { return m_buffers.length; }
	VkImageView getView()const { return m_buffers[m_current_buffer].view; }
	VkImage getImage()const { return m_buffers[m_current_buffer].image; }
	VkSwapchainKHR getSwapchain()const { return m_swapchain; }
	VkSemaphore getSemaphore()const { return m_imageAcquiredSemaphore; }

	bool create(GpuManager gpu
				, SurfaceManager surface
				, int w, int h
				, VkImageUsageFlags usageFlags = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
						VK_IMAGE_USAGE_TRANSFER_SRC_BIT)
	{
		// swapchain
		m_present_queue_family_index = gpu.get_present_queue_family_index();

		auto swapchainExtent = surface.getExtent(w, h);

		VkSwapchainCreateInfoKHR swapchain_ci;
		swapchain_ci.surface = surface.get();
		swapchain_ci.minImageCount = surface.getDesiredNumberOfSwapchainImages();
		swapchain_ci.imageFormat = gpu.getPrimaryFormat();
		swapchain_ci.imageExtent.width = swapchainExtent.width;
		swapchain_ci.imageExtent.height = swapchainExtent.height;
		swapchain_ci.preTransform = surface.getPreTransform();
		swapchain_ci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
		swapchain_ci.imageArrayLayers = 1;
		swapchain_ci.presentMode = surface.getSwapchainPresentMode();
		swapchain_ci.clipped = true;
		swapchain_ci.imageColorSpace = VK_COLORSPACE_SRGB_NONLINEAR_KHR;
		swapchain_ci.imageUsage = usageFlags;
		swapchain_ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
		swapchain_ci.queueFamilyIndexCount = 0;
		if (gpu.get_graphics_queue_family_index() != gpu.get_present_queue_family_index()) {
			// If the graphics and present queues are from different queue families,
			// we either have to explicitly transfer ownership of images between the
			// queues, or we have to create the swapchain with imageSharingMode
			// as VK_SHARING_MODE_CONCURRENT
			uint[2] queueFamilyIndices = [
				gpu.get_graphics_queue_family_index(),
				gpu.get_present_queue_family_index(),
			];
			swapchain_ci.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
			swapchain_ci.queueFamilyIndexCount = queueFamilyIndices.length;
			swapchain_ci.pQueueFamilyIndices = queueFamilyIndices.ptr;
		}
		auto res = vkCreateSwapchainKHR(m_device.get(), &swapchain_ci, null,
										&m_swapchain);
		if (res != VK_SUCCESS) {
			return false;
		}

		// semaphore
		res = vkCreateSemaphore(m_device.get(), &m_imageAcquiredSemaphoreCreateInfo,
								null, &m_imageAcquiredSemaphore);
		if (res != VK_SUCCESS) {
			return false;
		}

		// present queue
		vkGetDeviceQueue(m_device.get(), m_present_queue_family_index, 0, &m_present_queue);

		return true;
	}

	bool prepareImages(VkFormat format)
	{
		uint swapchainImageCount;
		auto res = vkGetSwapchainImagesKHR(m_device.get(), m_swapchain,
										   &swapchainImageCount, null);
		if (res != VK_SUCCESS) {
			return false;
		}
		if (swapchainImageCount == 0) {
			return false;
		}

		auto swapchainImages=new VkImage[swapchainImageCount];
		res = vkGetSwapchainImagesKHR(m_device.get(), m_swapchain,
									  &swapchainImageCount, swapchainImages.ptr);
		if (res != VK_SUCCESS) {
			return false;
		}

		for (uint i = 0; i < swapchainImageCount; i++)
		{
			VkImageViewCreateInfo color_image_view;
			color_image_view.format = format;
			color_image_view.components.r = VK_COMPONENT_SWIZZLE_R;
			color_image_view.components.g = VK_COMPONENT_SWIZZLE_G;
			color_image_view.components.b = VK_COMPONENT_SWIZZLE_B;
			color_image_view.components.a = VK_COMPONENT_SWIZZLE_A;
			color_image_view.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
			color_image_view.subresourceRange.baseMipLevel = 0;
			color_image_view.subresourceRange.levelCount = 1;
			color_image_view.subresourceRange.baseArrayLayer = 0;
			color_image_view.subresourceRange.layerCount = 1;
			color_image_view.viewType = VK_IMAGE_VIEW_TYPE_2D;
			color_image_view.flags = 0;
			color_image_view.image = swapchainImages[i];

			swap_chain_buffer sc_buffer;
			res = vkCreateImageView(m_device.get(), &color_image_view, null,
									&sc_buffer.view);
			if (res != VK_SUCCESS) {
				return false;
			}
			sc_buffer.image = swapchainImages[i];
			m_buffers~=sc_buffer;
		}

		return true;
	}

	///
	/// get current buffer
	/// set image layout to current buffer
	///
	bool update()
	{
		// Get the index of the next available swapchain image:
		auto res = vkAcquireNextImageKHR(m_device.get()
										 , m_swapchain
										 , ulong.max
										 , m_imageAcquiredSemaphore
										 , VkFence.init
										 , &m_current_buffer);
		// TODO: Deal with the VK_SUBOPTIMAL_KHR and VK_ERROR_OUT_OF_DATE_KHR
		// return codes
		if (res != VK_SUCCESS) {
			return false;
		}

		return true;
	}

	// Now present the image in the window
	bool present()
	{
		VkPresentInfoKHR present;
		present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
		present.pNext = null;
		present.swapchainCount = 1;
		present.pSwapchains = &m_swapchain;
		present.pImageIndices = &m_current_buffer;
		present.pWaitSemaphores = null;
		present.waitSemaphoreCount = 0;
		present.pResults = null;

		auto res = vkQueuePresentKHR(m_present_queue, &present);
		if (res != VK_SUCCESS) {
			return false;
		}

		return true;
	}
};


class PipelineResource
{
	DeviceManager m_device;

	// shader
	struct shader_source
	{
		VkShaderStageFlagBits stage;
		void[] spv;
		string entryPoint;
		VkShaderModuleCreateInfo m_moduleCreateInfo;
	};
	shader_source[] m_shaderSources;
	VkPipelineShaderStageCreateInfo[] m_shaderInfos;

	// descriptor
	VkDescriptorSetLayout m_desc_layout;
	VkDescriptorSet[] m_desc_set;
	VkDescriptorPool m_desc_pool;

	//
	VkPipelineLayout m_pipeline_layout;

	VkPipelineCache m_pipelineCache;

	// pipeline
	VkDynamicState[9/*VK_DYNAMIC_STATE_RANGE_SIZE*/] m_dynamicStateEnables;
	VkPipelineDynamicStateCreateInfo m_dynamicState;
	VkPipelineVertexInputStateCreateInfo m_vertexInputState;
	VkPipelineInputAssemblyStateCreateInfo m_inputAssemblyState;
	VkPipelineRasterizationStateCreateInfo m_rasterizationState;
	VkPipelineColorBlendStateCreateInfo m_colorBlendState;
	VkPipelineColorBlendAttachmentState[] m_colorBlendAttachmentState;
	VkPipelineViewportStateCreateInfo m_viewportState;
	VkPipelineDepthStencilStateCreateInfo m_depthStencilState;
	VkPipelineMultisampleStateCreateInfo m_multiSampleState;
	VkGraphicsPipelineCreateInfo m_pipelineInfo;
	VkPipeline m_pipeline;

public:
	this(DeviceManager device)
	{
		m_device=device;
	}

	~this()
	{
		vkDestroyDescriptorPool(m_device.get(), m_desc_pool, null);
		vkDestroyPipeline(m_device.get(), m_pipeline, null);
		vkDestroyPipelineCache(m_device.get(), m_pipelineCache, null);
		vkDestroyDescriptorSetLayout(m_device.get(), m_desc_layout, null);
		vkDestroyPipelineLayout(m_device.get(), m_pipeline_layout, null);
		foreach (ref stage; m_shaderInfos)
		{
			vkDestroyShaderModule(m_device.get(), stage._module, null);
		}
	}

	VkPipeline getPipeline()const { return m_pipeline; }
	VkPipelineLayout getPipelineLayout()const { return m_pipeline_layout; }
	VkDescriptorSet* getDescriptorSet() { return m_desc_set.ptr; }
	uint getDescriptorSetCount()const { return m_desc_set.length; }

	void addShader(VkShaderStageFlagBits stage
				, void[] spv
				, string entryPoint)
	{
		m_shaderSources~=shader_source();
		m_shaderSources[$-1].stage = stage;
		m_shaderSources[$-1].spv = spv;
		m_shaderSources[$-1].entryPoint = entryPoint;
		m_shaderSources[$-1].m_moduleCreateInfo.codeSize = m_shaderSources[$-1].spv.length;
		m_shaderSources[$-1].m_moduleCreateInfo.pCode = cast(uint*)m_shaderSources[$-1].spv.ptr;
	}

	bool createShader()
	{
		m_shaderInfos.length=m_shaderSources.length;
		for (size_t i=0; i<m_shaderSources.length; ++i)
		{
			m_shaderInfos[i].stage = m_shaderSources[i].stage;
			m_shaderInfos[i].pName = m_shaderSources[i].entryPoint.ptr;
			auto res = vkCreateShaderModule(m_device.get()
											, &m_shaderSources[i].m_moduleCreateInfo, null
											, &m_shaderInfos[i]._module);
			if (res != VK_SUCCESS) {
				return false;
			}
		}
		return true;
	}

	bool createUniformBufferDescriptor(VkDescriptorBufferInfo uniformbuffer_info)
	{
		// pool
		VkDescriptorPoolSize[1] type_count;
		type_count[0].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		type_count[0].descriptorCount = 1;
		VkDescriptorPoolCreateInfo descriptor_pool;
		descriptor_pool.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
		descriptor_pool.pNext = null;
		descriptor_pool.maxSets = 1;
		descriptor_pool.poolSizeCount = type_count.length;
		descriptor_pool.pPoolSizes = type_count.ptr;
		auto res = vkCreateDescriptorPool(m_device.get(), &descriptor_pool, null,
										  &m_desc_pool);
		if (res != VK_SUCCESS)
		{
			return false;
		}

		// descriptor
		VkDescriptorSetLayoutBinding[1] layout_bindings;
		layout_bindings[0].binding = 0;
		layout_bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		layout_bindings[0].descriptorCount = 1;
		layout_bindings[0].stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
		VkDescriptorSetLayoutCreateInfo descriptor_layout;
		descriptor_layout.bindingCount = layout_bindings.length;
		descriptor_layout.pBindings = layout_bindings.ptr;
		res = vkCreateDescriptorSetLayout(m_device.get(), &descriptor_layout, null,
										  &m_desc_layout);
		if (res != VK_SUCCESS) {
			return false;
		}

		// descriptor set
		const int NUM_DESCRIPTOR_SETS = 1;
		VkDescriptorSetAllocateInfo alloc_info;
		alloc_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
		alloc_info.pNext = null;
		alloc_info.descriptorSetCount = NUM_DESCRIPTOR_SETS;
		alloc_info.descriptorPool = m_desc_pool;
		alloc_info.pSetLayouts = &m_desc_layout;
		m_desc_set.length=NUM_DESCRIPTOR_SETS;
		res = vkAllocateDescriptorSets(m_device.get(), &alloc_info, m_desc_set.ptr);
		if (res != VK_SUCCESS)
		{
			return false;
		}

		VkWriteDescriptorSet[1] writes;
		writes[0].dstSet = m_desc_set[0];
		writes[0].descriptorCount = 1;
		writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		writes[0].pBufferInfo = &uniformbuffer_info;
		writes[0].dstArrayElement = 0;
		writes[0].dstBinding = 0;
		vkUpdateDescriptorSets(m_device.get(), writes.length, writes.ptr, 0, null);

		return true;
	}

	bool createPipelineLayout()
	{
		VkPipelineLayoutCreateInfo pipelineLayoutCreateInfo;
		pipelineLayoutCreateInfo.pushConstantRangeCount = 0;
		pipelineLayoutCreateInfo.setLayoutCount = 1;
		pipelineLayoutCreateInfo.pSetLayouts = &m_desc_layout;
		auto res = vkCreatePipelineLayout(m_device.get(), &pipelineLayoutCreateInfo, null,
										  &m_pipeline_layout);
		if (res != VK_SUCCESS)
		{
			return false;
		}
		return true;
	}

	bool createPipelineCache()
	{
		VkPipelineCacheCreateInfo pipelineCacheInfo;
		pipelineCacheInfo.initialDataSize = 0;
		pipelineCacheInfo.flags = 0;
		auto res = vkCreatePipelineCache(m_device.get(), &pipelineCacheInfo, null,
										 &m_pipelineCache);
		if (res != VK_SUCCESS)
		{
			return false;
		}
		return true;
	}

	void setupDynamicState()
	{
		m_dynamicState.pDynamicStates = m_dynamicStateEnables.ptr;
		m_dynamicState.dynamicStateCount = 0;
	}
	void setupVertexInput(ref VertexbufferDesc vertexbuffer)
	{
		m_vertexInputState.vertexBindingDescriptionCount = 1;
		m_vertexInputState.pVertexBindingDescriptions = &vertexbuffer.getBindingDesc();
		m_vertexInputState.vertexAttributeDescriptionCount = 2;
		m_vertexInputState.pVertexAttributeDescriptions = vertexbuffer.getAttribs();
	}
	void setupInputAssembly(VkPrimitiveTopology topology)
	{
		m_inputAssemblyState.primitiveRestartEnable = VK_FALSE;
		m_inputAssemblyState.topology = cast(VkPrimitiveTopology)3;
	}
	void setupRasterizationState()
	{
		m_rasterizationState.polygonMode = VK_POLYGON_MODE_FILL;
		m_rasterizationState.cullMode = VK_CULL_MODE_BACK_BIT;
		m_rasterizationState.frontFace = VK_FRONT_FACE_CLOCKWISE;
		m_rasterizationState.depthClampEnable = VK_TRUE;
		m_rasterizationState.rasterizerDiscardEnable = VK_FALSE;
		m_rasterizationState.depthBiasEnable = VK_FALSE;
		m_rasterizationState.depthBiasConstantFactor = 0;
		m_rasterizationState.depthBiasClamp = 0;
		m_rasterizationState.depthBiasSlopeFactor = 0;
		m_rasterizationState.lineWidth = 1.0f;
	}
	void setupColorBlendState()
	{
		m_colorBlendAttachmentState~=VkPipelineColorBlendAttachmentState();
		m_colorBlendAttachmentState[0].colorWriteMask = 0xf;
		m_colorBlendAttachmentState[0].blendEnable = VK_FALSE;
		m_colorBlendAttachmentState[0].alphaBlendOp = VK_BLEND_OP_ADD;
		m_colorBlendAttachmentState[0].colorBlendOp = VK_BLEND_OP_ADD;
		m_colorBlendAttachmentState[0].srcColorBlendFactor = VK_BLEND_FACTOR_ZERO;
		m_colorBlendAttachmentState[0].dstColorBlendFactor = VK_BLEND_FACTOR_ZERO;
		m_colorBlendAttachmentState[0].srcAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
		m_colorBlendAttachmentState[0].dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
		m_colorBlendState.attachmentCount = m_colorBlendAttachmentState.length;
		m_colorBlendState.pAttachments = m_colorBlendAttachmentState.ptr;
		m_colorBlendState.logicOpEnable = VK_FALSE;
		m_colorBlendState.logicOp = VK_LOGIC_OP_NO_OP;
		m_colorBlendState.blendConstants[0] = 1.0f;
		m_colorBlendState.blendConstants[1] = 1.0f;
		m_colorBlendState.blendConstants[2] = 1.0f;
		m_colorBlendState.blendConstants[3] = 1.0f;
	}
	void setupViewportState(int numViewports, int numScissors)
	{
		m_viewportState.viewportCount = numViewports;
		m_dynamicStateEnables[m_dynamicState.dynamicStateCount++] = VK_DYNAMIC_STATE_VIEWPORT;
		m_viewportState.scissorCount = numScissors;
		m_dynamicStateEnables[m_dynamicState.dynamicStateCount++] = VK_DYNAMIC_STATE_SCISSOR;
	}
	void setupDepthStencilState()
	{
		m_depthStencilState.depthTestEnable = VK_TRUE;
		m_depthStencilState.depthWriteEnable = VK_TRUE;
		m_depthStencilState.depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL;
		m_depthStencilState.depthBoundsTestEnable = VK_FALSE;
		m_depthStencilState.stencilTestEnable = VK_FALSE;
		m_depthStencilState.back.failOp = VK_STENCIL_OP_KEEP;
		m_depthStencilState.back.passOp = VK_STENCIL_OP_KEEP;
		m_depthStencilState.back.compareOp = VK_COMPARE_OP_ALWAYS;
		m_depthStencilState.back.compareMask = 0;
		m_depthStencilState.back.reference = 0;
		m_depthStencilState.back.depthFailOp = VK_STENCIL_OP_KEEP;
		m_depthStencilState.back.writeMask = 0;
		m_depthStencilState.minDepthBounds = 0;
		m_depthStencilState.maxDepthBounds = 0;
		m_depthStencilState.stencilTestEnable = VK_FALSE;
		m_depthStencilState.front = m_depthStencilState.back;
	}
	void setupMultisampleState(VkSampleCountFlagBits rasterizationSamples)
	{
		m_multiSampleState.rasterizationSamples = rasterizationSamples;
		m_multiSampleState.sampleShadingEnable = VK_FALSE;
		m_multiSampleState.alphaToCoverageEnable = VK_FALSE;
		m_multiSampleState.alphaToOneEnable = VK_FALSE;
		m_multiSampleState.minSampleShading = 0.0;
	}
	bool create(VkRenderPass renderPass)
	{
		m_pipelineInfo.basePipelineIndex = 0;
		m_pipelineInfo.flags = 0;
		m_pipelineInfo.pVertexInputState = &m_vertexInputState;
		m_pipelineInfo.pInputAssemblyState = &m_inputAssemblyState;
		m_pipelineInfo.pRasterizationState = &m_rasterizationState;
		m_pipelineInfo.pColorBlendState = &m_colorBlendState;
		m_pipelineInfo.pMultisampleState = &m_multiSampleState;
		m_pipelineInfo.pDynamicState = &m_dynamicState;
		m_pipelineInfo.pViewportState = &m_viewportState;
		m_pipelineInfo.pDepthStencilState = &m_depthStencilState;
		m_pipelineInfo.stageCount = m_shaderInfos.length;
		m_pipelineInfo.pStages = m_shaderInfos.ptr;
		m_pipelineInfo.renderPass = renderPass;
		m_pipelineInfo.subpass = 0;
		m_pipelineInfo.layout = m_pipeline_layout;
		auto res = vkCreateGraphicsPipelines(m_device.get(), m_pipelineCache, 1,
											 &m_pipelineInfo, null, &m_pipeline);
		if (res != VK_SUCCESS)
		{
			return false;
		}
		return true;
	}
};


class CommandBufferResource
{
	DeviceManager m_device;

	VkCommandPool m_cmd_pool;
	VkCommandBuffer[1] m_cmd_bufs;
	VkClearValue[2] m_clear_values;

	uint m_graphics_queue_family_index;
	VkQueue m_graphics_queue;

public:
	this(DeviceManager device)
	{
		m_device=device;
		m_clear_values[0].color.float32[0] = 0.2f;
		m_clear_values[0].color.float32[1] = 0.2f;
		m_clear_values[0].color.float32[2] = 0.2f;
		m_clear_values[0].color.float32[3] = 0.2f;
		m_clear_values[1].depthStencil.depth = 1.0f;
		m_clear_values[1].depthStencil.stencil = 0;
	}

	~this()
	{
		vkFreeCommandBuffers(m_device.get(), m_cmd_pool, m_cmd_bufs.length, m_cmd_bufs.ptr);
		vkDestroyCommandPool(m_device.get(), m_cmd_pool, null);
	}

	bool create(int graphics_queue_family_index) 
	{
		VkCommandPoolCreateInfo m_cmd_pool_info;
		m_cmd_pool_info.queueFamilyIndex = graphics_queue_family_index;
		m_cmd_pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
		auto res =
			vkCreateCommandPool(m_device.get(), &m_cmd_pool_info, null, &m_cmd_pool);
		if (res != VK_SUCCESS) {
			return false;
		}

		VkCommandBufferAllocateInfo m_cmdInfo;
		m_cmdInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
		m_cmdInfo.commandBufferCount = m_cmd_bufs.length;
		m_cmdInfo.commandPool = m_cmd_pool;
		res = vkAllocateCommandBuffers(m_device.get(), &m_cmdInfo, m_cmd_bufs.ptr);
		if (res != VK_SUCCESS) {
			return false;
		}

		vkGetDeviceQueue(m_device.get(), m_graphics_queue_family_index, 0, &m_graphics_queue);

		return true;
	}

	bool begin() 
	{
		VkCommandBufferBeginInfo cmd_buf_info;
		auto res = vkBeginCommandBuffer(m_cmd_bufs[0], &cmd_buf_info);
		if (res != VK_SUCCESS) {
			return false;
		}

		return true;
	}

	bool end() 
	{
		auto res = vkEndCommandBuffer(m_cmd_bufs[0]);
		if (res != VK_SUCCESS)
		{
			return false;
		}
		return true;
	}

	bool submit(VkDevice device, VkSemaphore semaphore
				// Amount of time, in nanoseconds, to wait for a command buffer to complete
				, uint64_t timeout= 100000000)
	{
		VkFenceCreateInfo fenceInfo;
		VkFence drawFence;
		auto res=vkCreateFence(device, &fenceInfo, null, &drawFence);
		if (res != VK_SUCCESS) {
			return false;
		}

		VkPipelineStageFlags pipe_stage_flags =
			VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

		VkSubmitInfo[1] submit_info;
		//submit_info[0].waitSemaphoreCount = 0;
		//submit_info[0].pWaitSemaphores;
		submit_info[0].waitSemaphoreCount = 1;
		submit_info[0].pWaitSemaphores = &semaphore;
		submit_info[0].pWaitDstStageMask = &pipe_stage_flags;
		submit_info[0].commandBufferCount = m_cmd_bufs.length;
		submit_info[0].pCommandBuffers = m_cmd_bufs.ptr;
		submit_info[0].signalSemaphoreCount = 0;

		res = vkQueueSubmit(m_graphics_queue, 1, submit_info.ptr, drawFence);
		if (res != VK_SUCCESS) {
			return false;
		}

		do {
			res =
				vkWaitForFences(device, 1, &drawFence, VK_TRUE, timeout);
		} while (res == VK_TIMEOUT);
		if (res != VK_SUCCESS) {
			return false;
		}

		vkDestroyFence(device, drawFence, null);

		return true;
	}

	void beginRenderPass(VkRenderPass render_pass, VkFramebuffer framebuffer
						 , VkRect2D rect)
	{
		VkRenderPassBeginInfo rp_begin;
		rp_begin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
		rp_begin.pNext = null;
		rp_begin.renderPass = render_pass;
		rp_begin.framebuffer = framebuffer;
		rp_begin.renderArea = rect;
		rp_begin.clearValueCount = m_clear_values.length;
		rp_begin.pClearValues = m_clear_values.ptr;
		vkCmdBeginRenderPass(m_cmd_bufs[0], &rp_begin, VK_SUBPASS_CONTENTS_INLINE);
	}

	void endRenderPass()
	{
		vkCmdEndRenderPass(m_cmd_bufs[0]);
	}

	void bindPipeline(VkPipeline pipeline, VkPipelineLayout pipeline_layout
					  , const VkDescriptorSet *pDesc, uint descCount)
	{
		vkCmdBindPipeline(m_cmd_bufs[0], VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
		vkCmdBindDescriptorSets(m_cmd_bufs[0], VK_PIPELINE_BIND_POINT_GRAPHICS
								, pipeline_layout, 0
								, descCount, pDesc
								, 0, null
								);
	}

	void bindVertexbuffer(VkBuffer buf)
	{
		VkDeviceSize[1] offsets;
		vkCmdBindVertexBuffers(m_cmd_bufs[0], 0
							   , 1, &buf, offsets.ptr);	
	}

	void initViewports(int width, int height) 
	{
		VkViewport viewport;
		viewport.height = cast(float)height;
		viewport.width = cast(float)width;
		viewport.minDepth = cast(float)0.0f;
		viewport.maxDepth = cast(float)1.0f;
		viewport.x = 0;
		viewport.y = 0;
		vkCmdSetViewport(m_cmd_bufs[0], 0, 1, &viewport);

		VkRect2D scissor;
		scissor.extent.width = width;
		scissor.extent.height = height;
		scissor.offset.x = 0;
		scissor.offset.y = 0;
		vkCmdSetScissor(m_cmd_bufs[0], 0, 1, &scissor);
	}

	void draw()
	{
		vkCmdDraw(m_cmd_bufs[0], 12 * 3, 1, 0, 0);
	}

	void setImageLayout(
						VkImage image,
						VkImageAspectFlags aspectMask,
						VkImageLayout old_image_layout,
						VkImageLayout new_image_layout)
	{
		VkImageMemoryBarrier image_memory_barrier;
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

		vkCmdPipelineBarrier(m_cmd_bufs[0], src_stages, dest_stages, 0, 0, null, 0, null,
							 1, &image_memory_barrier);
	}
};


int main()
{
	// logger
    auto defaultFileLogger=cast(FileLogger)sharedLog;
    sharedLog = new MyCustomLogger(defaultFileLogger);

	Glfw3Manager glfw;
	int w = 640;
	int h = 480;
	if(!glfw.initialize(w, h)){
		return 1;
	}
	log("glfw.initialized");

	log("DVulkanDerelict.load.");
	DVulkanDerelict.load();
	DVulkanDerelict.loadInitializationFunctions();

	// instance
	auto instance=InstanceManager.create("glfwvulkan", "vulkan engine");
	if (!instance) {
		return 3;
	}

	// gpu
	auto gpus = GpuManager.enumerate_gpu(instance.get());
    if(gpus.empty()){
        return 4;
    }
	auto gpu = gpus.front();

	// surface
	auto surface=new SurfaceManager(instance);
	if (!surface.create(GetModuleHandle(null), glfw.get_hwnd()))
	{
		return 6;
	}
	if (!gpu.prepare(surface.get())) {
		return 6;
	}
	if (!surface.getCapabilityFor(gpu.get())) {
		return 6;
	}

	// device
	auto device = new DeviceManager(instance);
	if(!device.create(gpu)){
        return 7;
    }

	auto swapchain=new SwapchainResource(device);
	if (!swapchain.create(gpu, surface, w, h)) {
		return 8;
	}
	if (!swapchain.prepareImages(gpu.getPrimaryFormat())) {
		return 8;
	}

	auto depth=new DepthbufferResource(device);
	if (!depth.create(gpu, w, h)) {
		return 9;
	}
	auto depth_memory=new DeviceMemoryResource(device);
	if (!depth_memory.allocate(gpu, depth.getMemoryRquirements(), 0)) {
		return 9;
	}
	if (!depth.bind(depth_memory.get())) {
		return 9;
	}
	if (!depth.createView()) {
		return 9;
	}

	auto framebuffer=new FramebufferResource(device);
	{
		auto imageSamples = depth.getSamples();
		framebuffer.attachColor(swapchain.getView(), gpu.getPrimaryFormat(), depth.getSamples());
	}
	{
		auto depthView = depth.getView();
		auto depthSamples = depth.getSamples();
		auto depthFormat = depth.getFormat();
		framebuffer.attachDepth(depthView, depthFormat, depthSamples);
	}
	framebuffer.pushSubpass(0, 1);
	if (!framebuffer.create(w, h))
	{
		return 10;
	}

	static const Vertex[] vertices = [

		Vertex(-0.5f, 0, 0.5, /**/1, 0, 0),
		Vertex( 0.5f, 0, 0.5, /**/0, 1, 0),
		Vertex(   0f, 0.5, 0.5, /**/0, 0, 1),

	];

	//auto m = calcMVP(w, h);
	static auto m=mat4!float.identity;

	auto vertex_desc=new VertexbufferDesc();
	vertex_desc.pushAttrib();
	vertex_desc.pushAttrib();

	auto vertex_buffer=new BufferResource(device);
	if (!vertex_buffer.create(gpu, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, Vertex.sizeof * vertices.length)) {
		return 11;
	}
	auto vertex_memory=new DeviceMemoryResource(device);
	if (!vertex_memory.allocate(gpu, vertex_buffer.getMemoryRequirements()
								, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
									return 11;
								}
	{
		if (!vertex_memory.map!((byte *pData, uint size) {
			memcpy(pData, vertices.ptr, size);
		})()) {
			return 11;
		}
		if (!vertex_buffer.bind(vertex_memory.get())) {
			return 11;
		}
	}

	auto uniform_buffer=new BufferResource(device);
	if (!uniform_buffer.create(gpu, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, mat4!float.sizeof)) {
		return 12;
	}
	auto uniform_memory=new DeviceMemoryResource(device);
	if (!uniform_memory.allocate(gpu, uniform_buffer.getMemoryRequirements()
								 , VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
									 return 12;
								 }
	{
		if (!uniform_memory.map!((byte *p, uint size) {
			memcpy(p, &m, size);
		})()) {
			return 12;
		}
		if (!uniform_buffer.bind(uniform_memory.get())) {
			return 12;
		}
	}

	auto pipeline=new PipelineResource(device);

	//init_glslang();
	pipeline.addShader(VK_SHADER_STAGE_VERTEX_BIT
					   , read("15-draw_cube.vert.spv"), "main");
	pipeline.addShader(VK_SHADER_STAGE_FRAGMENT_BIT
					   , read("15-draw_cube.frag.spv"), "main");
	//finalize_glslang();

	if (!pipeline.createShader()) {
		return 13;
	}
	if (!pipeline.createUniformBufferDescriptor(uniform_buffer.getDescInfo())) {
		return 13;
	}
	if (!pipeline.createPipelineLayout()) {
		return 13;
	}
	if (!pipeline.createPipelineCache()) {
		return 13;
	}
	pipeline.setupDynamicState();
	pipeline.setupVertexInput(vertex_desc);
	pipeline.setupInputAssembly(VkPrimitiveTopology.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
	pipeline.setupRasterizationState();
	pipeline.setupColorBlendState();
	// Number of viewports and number of scissors have to be the same
	// at m_pipelineInfo creation and in any call to set them dynamically
	// They also have to be the same as each other
	const int NUM_VIEWPORTS = 1;
	const int NUM_SCISSORS = NUM_VIEWPORTS;
	pipeline.setupViewportState(NUM_VIEWPORTS, NUM_SCISSORS);
	pipeline.setupDepthStencilState();
	pipeline.setupMultisampleState(VK_SAMPLE_COUNT_1_BIT);
	if (!pipeline.create(framebuffer.getRenderPass())){
		return 13;
	}

	auto cmd=new CommandBufferResource(device);
	if (!cmd.create(gpu.get_graphics_queue_family_index())) {
		return 14;
	}

	while (glfw.newFrame())
	{
		swapchain.update();

		// start
		if (cmd.begin())
		{
			// Set the image layout to depth stencil optimal
			cmd.setImageLayout(
							   depth.getImage()
							   , depth.getAspect() //m_view_info.subresourceRange.aspectMask
							   , VK_IMAGE_LAYOUT_UNDEFINED
							   , VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
							   );

			cmd.setImageLayout(
							   swapchain.getImage()
							   , VK_IMAGE_ASPECT_COLOR_BIT
							   , VK_IMAGE_LAYOUT_UNDEFINED
							   , VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
							   );

			VkRect2D rect;
			rect.extent.width=w;
			rect.extent.height=h;
			cmd.beginRenderPass(
								framebuffer.getRenderPass()
								, framebuffer.getFramebuffer()
								, rect);
			{
				cmd.bindPipeline(
								 pipeline.getPipeline(), pipeline.getPipelineLayout()
								 , pipeline.getDescriptorSet(), pipeline.getDescriptorSetCount()
								 );

				cmd.bindVertexbuffer(
									 vertex_buffer.getBuffer());

				cmd.initViewports(w, h);

				cmd.draw();
			}
			cmd.endRenderPass();

			if (!cmd.end()) {
				return 16;
			}
			if (!cmd.submit(device.get(), swapchain.getSemaphore())) {
				return 17;
			}

			swapchain.present();
		}
	}

	return 0;
}
