import logger;
import derelict.glfw3.glfw3;
import derelict.glfw3.glfw3;
import dvulkan;
import std.experimental.logger;
import std.exception;
import std.algorithm;
import std.range;


struct VulkanManager
{
    VkInstance inst;
    VkPhysicalDevice[] gpus;
	VkQueueFamilyProperties[] queue_props;
	int queueFamilyIndex=-1;
	VkDevice device;

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

    bool initialize()
    {
        {
            // 01

            // initialize the VkApplicationInfo structure
            VkApplicationInfo app_info = {
                pApplicationName: "VulkanOnD",
                apiVersion: VK_MAKE_VERSION(1, 0, 2),
            };

            // initialize the VkInstanceCreateInfo structure
            VkInstanceCreateInfo inst_info = {
                pApplicationInfo: &app_info,
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

        {
            // 02
            uint gpu_count = 1;
            auto res =
                vkEnumeratePhysicalDevices(inst, &gpu_count, null);
            enforce(gpu_count, "gpu_count");

            gpus=new VkPhysicalDevice[gpu_count];
            res = vkEnumeratePhysicalDevices(inst, &gpu_count, gpus.ptr);
            enforce(!res && gpu_count >= 1, "vkEnumeratePhysicalDevices");
			info("02-enumerate_devices");
        }

		{
			// 03
			uint queue_family_count;
			vkGetPhysicalDeviceQueueFamilyProperties(gpus[0],
													 &queue_family_count, null);
			enforce(queue_family_count >= 1, "vkGetPhysicalDeviceQueueFamilyProperties");

			queue_props=new VkQueueFamilyProperties[queue_family_count];
			vkGetPhysicalDeviceQueueFamilyProperties(
													 gpus[0], &queue_family_count, queue_props.ptr);
			enforce(queue_family_count >= 1);

			queueFamilyIndex = -1;
			for(int i=0; i<queue_props.length; ++i)
			{
				if(queue_props[i].queueFlags & VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT){
					queueFamilyIndex=i;
					break;
				}
			}
			enforce(queueFamilyIndex>= 0);

			VkDeviceQueueCreateInfo queue_info={
				queueCount: 1,
				pQueuePriorities: [0.0f],
			};

			VkDeviceCreateInfo device_info = {
				queueCreateInfoCount: 1,
				pQueueCreateInfos: &queue_info,
			};

			auto res =
				vkCreateDevice(gpus[0], &device_info, null, &device);
			enforce(res == VkResult.VK_SUCCESS, "vkCreateDevice");

			info("03-init_device");
		}

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
	}

	~this()
	{
		log("~Glfw3Manager");
		glfwTerminate();
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


    VulkanManager vulkan;
    if(!vulkan.initialize()){
        return;
    }
    log("vulkan.initialized");

	Glfw3Manager glfw;
	if(!glfw.initialize()){
		return;
	}
	log("glfw.initialized");

	while(glfw.newFrame()){
		//
	}
}
