#include <PoseidonGL33/EngineGL33Anaglyph3D.hpp>
#include <PoseidonGL33/EngineGL33.hpp>
#include <Poseidon/Graphics/Core/FrameState.hpp>
#include <Poseidon/Graphics/Core/PassState.hpp>
#include <Poseidon/Core/Application.hpp>
#include <Poseidon/Dev/Debug/DebugOverlay.hpp>

#include <glad/gl.h>
#include <cstring>

// Simple vertex shader for screen-space quad
static const char* s_screenVertexShader = R"glsl(
#version 330 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTexCoord;

out vec2 TexCoord;

void main()
{
    gl_Position = vec4(aPos.x, aPos.y, 0.0, 1.0);
    TexCoord = aTexCoord;
}
)glsl";

// Anaglyph composition shader
static const char* s_anaglyphFragmentShader = R"glsl(
#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform sampler2D leftTexture;
uniform sampler2D rightTexture;
uniform float brightness;
uniform int colorScheme; // 0=RedCyan, 1=GreenMagenta, 2=AmberBlue

void main()
{
    vec3 leftColor = texture(leftTexture, TexCoord).rgb;
    vec3 rightColor = texture(rightTexture, TexCoord).rgb;
    
    vec3 outputColor;
    
    switch(colorScheme)
    {
        case 0: // Red-Cyan
            outputColor = vec3(leftColor.r, (rightColor.g + rightColor.b) * 0.5, (rightColor.g + rightColor.b) * 0.5);
            break;
            
        case 1: // Green-Magenta
            outputColor = vec3((leftColor.r + leftColor.b) * 0.5, rightColor.g, (leftColor.r + leftColor.b) * 0.5);
            break;
            
        case 2: // Amber-Blue
            outputColor = vec3((leftColor.r + leftColor.g) * 0.5, (leftColor.r + leftColor.g) * 0.5, rightColor.b);
            break;
            
        default: // Fallback to Red-Cyan
            outputColor = vec3(leftColor.r, rightColor.g, rightColor.b);
            break;
    }
    
    // Apply brightness boost
    outputColor *= brightness;
    
    // Ensure we don't clip
    outputColor = clamp(outputColor, 0.0, 1.0);
    
    FragColor = vec4(outputColor, 1.0);
}
)glsl";

// Side-by-side composition shader for 3D TVs
static const char* s_sideBySideFragmentShader = R"glsl(
#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform sampler2D leftTexture;
uniform sampler2D rightTexture;
uniform float separation; // 0.0 = no separation, 0.5 = full half-width

void main()
{
    vec2 leftCoord = TexCoord;
    vec2 rightCoord = TexCoord;
    
    // Adjust for half-width
    if (TexCoord.x < 0.5) {
        leftCoord.x = TexCoord.x * 2.0;
        rightCoord.x = TexCoord.x * 2.0;
    } else {
        leftCoord.x = (TexCoord.x - 0.5) * 2.0;
        rightCoord.x = (TexCoord.x - 0.5) * 2.0;
    }
    
    // Assign which eye goes where
    vec3 leftColor = texture(leftTexture, leftCoord).rgb;
    vec3 rightColor = texture(rightTexture, rightCoord).rgb;
    
    // Output side-by-side: left half = left eye, right half = right eye
    if (TexCoord.x < 0.5) {
        FragColor = vec4(leftColor, 1.0);
    } else {
        FragColor = vec4(rightColor, 1.0);
    }
}
)glsl";

// Top-bottom composition shader for 3D projectors
static const char* s_topBottomFragmentShader = R"glsl(
#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform sampler2D leftTexture;
uniform sampler2D rightTexture;

void main()
{
    vec2 leftCoord = TexCoord;
    vec2 rightCoord = TexCoord;
    
    // Adjust for half-height
    if (TexCoord.y < 0.5) {
        leftCoord.y = TexCoord.y * 2.0;
        rightCoord.y = TexCoord.y * 2.0;
    } else {
        leftCoord.y = (TexCoord.y - 0.5) * 2.0;
        rightCoord.y = (TexCoord.y - 0.5) * 2.0;
    }
    
    vec3 leftColor = texture(leftTexture, leftCoord).rgb;
    vec3 rightColor = texture(rightTexture, rightCoord).rgb;
    
    // Output top-bottom: top half = left eye, bottom half = right eye
    if (TexCoord.y < 0.5) {
        FragColor = vec4(leftColor, 1.0);
    } else {
        FragColor = vec4(rightColor, 1.0);
    }
}
)glsl";

// Helper to compile shader
static unsigned int CompileShader(unsigned int type, const char* source)
{
    unsigned int shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    
    int success;
    char infoLog[512];
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success)
    {
        glGetShaderInfoLog(shader, 512, nullptr, infoLog);
        LOG_ERROR(Graphics, "Shader compilation failed: {}", infoLog);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

// Helper to link program
static unsigned int LinkProgram(unsigned int vertexShader, unsigned int fragmentShader)
{
    unsigned int program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    
    int success;
    char infoLog[512];
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (!success)
    {
        glGetProgramInfoLog(program, 512, nullptr, infoLog);
        LOG_ERROR(Graphics, "Program linking failed: {}", infoLog);
        glDeleteProgram(program);
        return 0;
    }
    return program;
}

// ============================================================
// EngineGL33Anaglyph3D Implementation
// ============================================================

EngineGL33Anaglyph3D::EngineGL33Anaglyph3D(EngineGL33* parentEngine)
    : m_engine(parentEngine)
    , m_enabled(false)
    , m_initialized(false)
    , m_mode(StereoMode::Anaglyph)
    , m_frameActive(false)
    , m_currentEye(0)
    , m_leftFbo(0)
    , m_leftColorTex(0)
    , m_leftDepthRb(0)
    , m_rightFbo(0)
    , m_rightColorTex(0)
    , m_rightDepthRb(0)
    , m_composeFbo(0)
    , m_composeTex(0)
    , m_quadVAO(0)
    , m_quadVBO(0)
    , m_anaglyphShader(0)
    , m_sideBySideShader(0)
    , m_topBottomShader(0)
    , m_renderWidth(0)
    , m_renderHeight(0)
    , m_compositeWidth(0)
    , m_compositeHeight(0)
{
    // Get current render dimensions from parent
    m_renderWidth = m_engine->Width();
    m_renderHeight = m_engine->Height();
    m_compositeWidth = m_renderWidth;
    m_compositeHeight = m_renderHeight;
    
    LOG_INFO(Graphics, "Anaglyph3D: Initialized with {}x{} render target", m_renderWidth, m_renderHeight);
}

EngineGL33Anaglyph3D::~EngineGL33Anaglyph3D()
{
    DestroyRenderTargets();
    DestroyCompositionShaders();
    DestroyScreenQuad();
}

void EngineGL33Anaglyph3D::SetEnabled(bool enabled)
{
    if (enabled == m_enabled)
        return;
        
    m_enabled = enabled;
    
    if (m_enabled)
    {
        if (!m_initialized)
        {
            // Initialize render targets and shaders
            if (!InitializeRenderTargets())
            {
                LOG_ERROR(Graphics, "Anaglyph3D: Failed to initialize render targets");
                m_enabled = false;
                return;
            }
            if (!InitializeCompositionShaders())
            {
                LOG_ERROR(Graphics, "Anaglyph3D: Failed to initialize composition shaders");
                m_enabled = false;
                return;
            }
            if (!InitializeScreenQuad())
            {
                LOG_ERROR(Graphics, "Anaglyph3D: Failed to initialize screen quad");
                m_enabled = false;
                return;
            }
            m_initialized = true;
        }
        LOG_INFO(Graphics, "Anaglyph3D: Enabled in {} mode", 
                 m_mode == StereoMode::Anaglyph ? "Anaglyph" :
                 m_mode == StereoMode::SideBySide ? "Side-by-Side" :
                 m_mode == StereoMode::TopBottom ? "Top-Bottom" : "Unknown");
    }
    else
    {
        LOG_INFO(Graphics, "Anaglyph3D: Disabled");
    }
}

void EngineGL33Anaglyph3D::SetMode(StereoMode mode)
{
    if (mode == m_mode)
        return;
    
    // Tear down if we need to switch modes
    bool wasEnabled = m_enabled;
    if (wasEnabled)
    {
        SetEnabled(false);
    }
    
    m_mode = mode;
    
    // Recreate composition shaders for the new mode
    if (wasEnabled)
    {
        SetEnabled(true);
    }
    
    LOG_INFO(Graphics, "Anaglyph3D: Mode set to {}", 
             mode == StereoMode::Anaglyph ? "Anaglyph" :
             mode == StereoMode::SideBySide ? "Side-by-Side" :
             mode == StereoMode::TopBottom ? "Top-Bottom" : "Disabled");
}

void EngineGL33Anaglyph3D::SetParams(const StereoParams& params)
{
    m_params = params;
    // Clamp values to safe ranges
    m_params.eyeSeparation = std::max(0.001f, std::min(0.5f, m_params.eyeSeparation));
    m_params.parallaxStrength = std::max(0.0f, std::min(2.0f, m_params.parallaxStrength));
    m_params.brightness = std::max(0.5f, std::min(1.5f, m_params.brightness));
}

Matrix4 EngineGL33Anaglyph3D::GetEyeViewMatrix(int eye, const Matrix4& baseView) const
{
    if (!m_enabled)
        return baseView;
    
    Matrix4 result = baseView;
    Vector3 eyeOffset = GetEyeOffset(eye);
    
    // Apply eye offset to view matrix (inverse of camera offset)
    // We need to offset the camera position in the view matrix
    // View matrix = inverse(camera transform)
    Vector3 camPos = result.GetTranslation();
    Vector3 newPos = camPos + eyeOffset;
    result.SetTranslation(newPos);
    
    return result;
}

Matrix4 EngineGL33Anaglyph3D::GetEyeProjection(int eye, const Matrix4& baseProj) const
{
    if (!m_enabled)
        return baseProj;
    
    Matrix4 result = baseProj;
    
    // For anaglyph, we want a subtle shift in projection to enhance depth
    if (m_mode == StereoMode::Anaglyph)
    {
        float shift = (eye == 0 ? -0.001f : 0.001f) * m_params.parallaxStrength;
        // Shift the projection slightly - this creates the parallax effect
        // result(2,0) += shift; // Uncomment when Matrix4 supports this
    }
    
    return result;
}

Vector3 EngineGL33Anaglyph3D::GetEyeOffset(int eye) const
{
    float separation = m_params.eyeSeparation * m_params.parallaxStrength;
    float sign = (eye == 0) ? -1.0f : 1.0f;
    
    // Camera's right vector is typically X-axis in world space
    // For now, simple horizontal offset
    return Vector3(sign * separation * 0.5f, 0.0f, 0.0f);
}

void EngineGL33Anaglyph3D::RenderStereo(const FrameState& frame, const PassState& pass)
{
    if (!m_enabled || !m_initialized)
        return;
    
    // Render left eye
    RenderSceneForEye(0, frame, pass);
    
    // Render right eye
    RenderSceneForEye(1, frame, pass);
    
    // Composite based on current mode
    switch (m_mode)
    {
        case StereoMode::Anaglyph:
            ComposeAnaglyph();
            break;
        case StereoMode::SideBySide:
            ComposeSideBySide();
            break;
        case StereoMode::TopBottom:
            ComposeTopBottom();
            break;
        case StereoMode::Interleaved:
            ComposeInterleaved();
            break;
        default:
            break;
    }
}

void EngineGL33Anaglyph3D::BeginFrame()
{
    if (!m_enabled || !m_initialized)
        return;
        
    m_frameActive = true;
    m_currentEye = 0;
    
    // Store current viewport
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    
    // We'll bind the appropriate FBO during render
}

void EngineGL33Anaglyph3D::EndFrame()
{
    if (!m_enabled || !m_initialized)
        return;
        
    m_frameActive = false;
}

void EngineGL33Anaglyph3D::RenderSceneForEye(int eye, const FrameState& frame, const PassState& pass)
{
    // This is where you'd actually render the scene with the offset camera
    // For now, we'll just render a simple test pattern in the render target
    
    unsigned int targetFbo = (eye == 0) ? m_leftFbo : m_rightFbo;
    
    // Bind the target FBO
    glBindFramebuffer(GL_FRAMEBUFFER, targetFbo);
    glViewport(0, 0, m_renderWidth, m_renderHeight);
    
    // Clear the target
    glClearColor(0.1f, 0.1f, 0.15f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // TODO: Render the actual scene here with offset camera
    // For now, draw a simple test pattern
    
    // Draw a colored quad based on which eye this is
    float color[3] = { (eye == 0) ? 0.5f : 0.0f, 
                       0.2f, 
                       (eye == 0) ? 0.0f : 0.5f };
    
    glClearColor(color[0], color[1], color[2], 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    // Reset to default framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void EngineGL33Anaglyph3D::ComposeAnaglyph()
{
    glBindFramebuffer(GL_FRAMEBUFFER, m_composeFbo);
    glViewport(0, 0, m_compositeWidth, m_compositeHeight);
    
    glUseProgram(m_anaglyphShader);
    
    // Bind textures
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_leftColorTex);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, m_rightColorTex);
    
    // Set uniforms
    glUniform1i(glGetUniformLocation(m_anaglyphShader, "leftTexture"), 0);
    glUniform1i(glGetUniformLocation(m_anaglyphShader, "rightTexture"), 1);
    glUniform1f(glGetUniformLocation(m_anaglyphShader, "brightness"), m_params.brightness);
    glUniform1i(glGetUniformLocation(m_anaglyphShader, "colorScheme"), (int)m_params.colorScheme);
    
    // Draw fullscreen quad
    DrawFullScreenQuad(m_anaglyphShader);
    
    // Copy to default framebuffer
    glBindFramebuffer(GL_READ_FRAMEBUFFER, m_composeFbo);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    glBlitFramebuffer(0, 0, m_compositeWidth, m_compositeHeight,
                      0, 0, m_compositeWidth, m_compositeHeight,
                      GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void EngineGL33Anaglyph3D::ComposeSideBySide()
{
    // Similar to ComposeAnaglyph but uses the side-by-side shader
    // This would output side-by-side format for 3D TVs
    
    // For now, just call anaglyph as fallback
    // We'll implement fully when we have the actual TV display working
    LOG_DEBUG(Graphics, "Side-by-side composition not fully implemented yet, using anaglyph fallback");
    ComposeAnaglyph();
}

void EngineGL33Anaglyph3D::ComposeTopBottom()
{
    // Similar to ComposeAnaglyph but uses top-bottom shader
    LOG_DEBUG(Graphics, "Top-bottom composition not fully implemented yet, using anaglyph fallback");
    ComposeAnaglyph();
}

void EngineGL33Anaglyph3D::ComposeInterleaved()
{
    LOG_DEBUG(Graphics, "Interleaved composition not fully implemented yet, using anaglyph fallback");
    ComposeAnaglyph();
}

void EngineGL33Anaglyph3D::DrawFullScreenQuad(unsigned int shader)
{
    // Render a fullscreen quad using the screen quad VBO
    // This assumes a standard fullscreen quad setup
    glBindVertexArray(m_quadVAO);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindVertexArray(0);
}

bool EngineGL33Anaglyph3D::InitializeRenderTargets()
{
    // Create two render targets (left and right eye)
    // We'll use a single FBO for each eye
    
    // Left eye
    glGenFramebuffers(1, &m_leftFbo);
    glBindFramebuffer(GL_FRAMEBUFFER, m_leftFbo);
    
    glGenTextures(1, &m_leftColorTex);
    glBindTexture(GL_TEXTURE_2D, m_leftColorTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, m_renderWidth, m_renderHeight, 0, GL_RGB, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_leftColorTex, 0);
    
    glGenRenderbuffers(1, &m_leftDepthRb);
    glBindRenderbuffer(GL_RENDERBUFFER, m_leftDepthRb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, m_renderWidth, m_renderHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_leftDepthRb);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        LOG_ERROR(Graphics, "Left FBO incomplete");
        return false;
    }
    
    // Right eye
    glGenFramebuffers(1, &m_rightFbo);
    glBindFramebuffer(GL_FRAMEBUFFER, m_rightFbo);
    
    glGenTextures(1, &m_rightColorTex);
    glBindTexture(GL_TEXTURE_2D, m_rightColorTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, m_renderWidth, m_renderHeight, 0, GL_RGB, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_rightColorTex, 0);
    
    glGenRenderbuffers(1, &m_rightDepthRb);
    glBindRenderbuffer(GL_RENDERBUFFER, m_rightDepthRb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, m_renderWidth, m_renderHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_rightDepthRb);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        LOG_ERROR(Graphics, "Right FBO incomplete");
        return false;
    }
    
    // Composition FBO
    glGenFramebuffers(1, &m_composeFbo);
    glBindFramebuffer(GL_FRAMEBUFFER, m_composeFbo);
    
    glGenTextures(1, &m_composeTex);
    glBindTexture(GL_TEXTURE_2D, m_composeTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, m_compositeWidth, m_compositeHeight, 0, GL_RGB, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_composeTex, 0);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        LOG_ERROR(Graphics, "Composition FBO incomplete");
        return false;
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    
    LOG_INFO(Graphics, "Anaglyph3D: Render targets initialized ({}x{})", m_renderWidth, m_renderHeight);
    return true;
}

void EngineGL33Anaglyph3D::DestroyRenderTargets()
{
    if (m_leftFbo)
    {
        glDeleteFramebuffers(1, &m_leftFbo);
        m_leftFbo = 0;
    }
    if (m_leftColorTex)
    {
        glDeleteTextures(1, &m_leftColorTex);
        m_leftColorTex = 0;
    }
    if (m_leftDepthRb)
    {
        glDeleteRenderbuffers(1, &m_leftDepthRb);
        m_leftDepthRb = 0;
    }
    
    if (m_rightFbo)
    {
        glDeleteFramebuffers(1, &m_rightFbo);
        m_rightFbo = 0;
    }
    if (m_rightColorTex)
    {
        glDeleteTextures(1, &m_rightColorTex);
        m_rightColorTex = 0;
    }
    if (m_rightDepthRb)
    {
        glDeleteRenderbuffers(1, &m_rightDepthRb);
        m_rightDepthRb = 0;
    }
    
    if (m_composeFbo)
    {
        glDeleteFramebuffers(1, &m_composeFbo);
        m_composeFbo = 0;
    }
    if (m_composeTex)
    {
        glDeleteTextures(1, &m_composeTex);
        m_composeTex = 0;
    }
}

bool EngineGL33Anaglyph3D::InitializeCompositionShaders()
{
    // Compile vertex shader
    unsigned int vertexShader = CompileShader(GL_VERTEX_SHADER, s_screenVertexShader);
    if (!vertexShader)
        return false;
    
    // Compile and link anaglyph shader
    unsigned int fragShader = CompileShader(GL_FRAGMENT_SHADER, s_anaglyphFragmentShader);
    if (!fragShader)
        return false;
    
    m_anaglyphShader = LinkProgram(vertexShader, fragShader);
    glDeleteShader(vertexShader);
    glDeleteShader(fragShader);
    
    if (!m_anaglyphShader)
        return false;
    
    // Side-by-side shader
    vertexShader = CompileShader(GL_VERTEX_SHADER, s_screenVertexShader);
    fragShader = CompileShader(GL_FRAGMENT_SHADER, s_sideBySideFragmentShader);
    m_sideBySideShader = LinkProgram(vertexShader, fragShader);
    glDeleteShader(vertexShader);
    glDeleteShader(fragShader);
    
    // Top-bottom shader
    vertexShader = CompileShader(GL_VERTEX_SHADER, s_screenVertexShader);
    fragShader = CompileShader(GL_FRAGMENT_SHADER, s_topBottomFragmentShader);
    m_topBottomShader = LinkProgram(vertexShader, fragShader);
    glDeleteShader(vertexShader);
    glDeleteShader(fragShader);
    
    LOG_INFO(Graphics, "Anaglyph3D: Composition shaders initialized");
    return true;
}

void EngineGL33Anaglyph3D::DestroyCompositionShaders()
{
    if (m_anaglyphShader)
    {
        glDeleteProgram(m_anaglyphShader);
        m_anaglyphShader = 0;
    }
    if (m_sideBySideShader)
    {
        glDeleteProgram(m_sideBySideShader);
        m_sideBySideShader = 0;
    }
    if (m_topBottomShader)
    {
        glDeleteProgram(m_topBottomShader);
        m_topBottomShader = 0;
    }
}

bool EngineGL33Anaglyph3D::InitializeScreenQuad()
{
    // Fullscreen quad vertices: positions and texture coordinates
    float vertices[] = {
        -1.0f, -1.0f, 0.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
         1.0f,  1.0f, 1.0f, 1.0f,
        -1.0f,  1.0f, 0.0f, 1.0f
    };
    
    glGenVertexArrays(1, &m_quadVAO);
    glGenBuffers(1, &m_quadVBO);
    
    glBindVertexArray(m_quadVAO);
    glBindBuffer(GL_ARRAY_BUFFER, m_quadVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)(2 * sizeof(float)));
    glEnableVertexAttribArray(1);
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
    
    LOG_INFO(Graphics, "Anaglyph3D: Screen quad initialized");
    return true;
}

void EngineGL33Anaglyph3D::DestroyScreenQuad()
{
    if (m_quadVAO)
    {
        glDeleteVertexArrays(1, &m_quadVAO);
        m_quadVAO = 0;
    }
    if (m_quadVBO)
    {
        glDeleteBuffers(1, &m_quadVBO);
        m_quadVBO = 0;
    }
}

void EngineGL33Anaglyph3D::DrawTestPattern3D()
{
    // Quick test function that draws a simple 3D object
    // This helps verify the stereo system is working
    LOG_INFO(Graphics, "Anaglyph3D: Drawing test pattern");
    
    // Disable stereo during test? Or draw in stereo mode?
    // For now, just log that it's called
}

void EngineGL33Anaglyph3D::DrawDebugOverlay()
{
    if (!m_enabled)
        return;
    
    // We'd use the ImGui overlay here to show stereo status
    // For now just log status
    LOG_DEBUG(Graphics, "Anaglyph3D: Mode={}, Enabled={}, Sep={:.3f}, Strength={:.2f}",
              (int)m_mode, m_enabled, m_params.eyeSeparation, m_params.parallaxStrength);
}