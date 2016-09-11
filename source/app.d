import logger;
import derelict.glfw3.glfw3;
import derelict.glfw3.glfw3;
import dvulkan;
import std.experimental.logger;


struct VulkanManager
{
    VkInstance inst;

	static this()
	{
		log("DVulkanDerelict.load.");
		DVulkanDerelict.load();
		DVulkanDerelict.loadInitializationFunctions();
	}

    ~this()
    {
		log("~VulkanManager");
        vkDestroyInstance(inst, null);
    }

    bool initialize()
    {
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
		log(vkDestroyInstance);

        info("vkCreateInstance success");

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
											  , "GLFW 3 D-lang"
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
