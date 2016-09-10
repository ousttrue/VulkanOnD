import derelict.glfw3.glfw3;
import std.experimental.logger;

void main() 
{
    log("Load the GLFW 3 library.");
    DerelictGLFW3.load();

	glfwInit();
 
	const window_width  = 800;
	const window_height = 600;
	GLFWwindow *window = glfwCreateWindow(window_width, window_height
            , "GLFW 3 D-lang"
            , null, null);
 
	while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();
	}
 
	glfwTerminate();
}

