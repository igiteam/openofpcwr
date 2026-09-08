#ifdef _MSC_VER
#pragma once
#endif

#ifndef __ENGINE_GL33_STEREO3D_HPP
#define __ENGINE_GL33_STEREO3D_HPP

#include <Poseidon/Core/Types.hpp>
#include <Poseidon/Math/Matrix4.hpp>
#include <Poseidon/Math/Vector3.hpp>
#include <Poseidon/Graphics/Core/FrameState.hpp>
#include <Poseidon/Graphics/Core/PassState.hpp>
#include <Poseidon/Graphics/Rendering/Lighting/Lights.hpp>
#include <memory>
#include <vector>

// Forward declarations
class EngineGL33;
class TextureGL33;
struct TLVertex;

/**
 * Stereoscopic 3D rendering modes for modern 3D displays
 */
enum class Stereo3DMode
{
    Disabled = 0,
    SideBySide,          // Standard for 3D TVs (Panavision, Samsung, LG)
    TopBottom,           // For 3D projectors
    FramePacking,        // HDMI 1.4a frame-packing (requires HDMI 3D handshake)
    Anaglyph,            // Red-Cyan glasses (fallback/compatibility)
    Interleaved,         // For passive 3D displays with checkerboard pattern
    DualOutput           // Two separate outputs (dual-projector setups)
};

/**
 * Advanced stereoscopic parameters
 */
struct Stereo3DParams
{
    // Camera separation
    float eyeSeparation = 0.064f;    // Average human IPD ~64mm in world units
    float convergenceDistance = 30.0f; // Where the eyes converge (in world units)
    float focalLength = 50.0f;        // Focal length for depth-of-field effects
    
    // Depth mapping
    float depthScale = 1.0f;          // Overall depth intensity
    float zeroParallaxPlane = 30.0f;  // Where objects appear at screen depth
    float maxParallax = 0.05f;        // Maximum screen parallax (in normalized coords)
    
    // Comfort settings
    float comfortZone = 0.8f;         // Reduce depth in peripheral vision (0-1)
    bool autoConvergence = true;      // Auto-adjust convergence based on scene
    float autoConvergenceSpeed = 0.1f; // Speed of auto-convergence adjustment
    
    // Display specific
    float screenWidth = 2.0f;         // Screen width in meters (for accurate parallax)
    float viewingDistance = 3.0f;     // Viewer distance from screen
    
    // Side-by-side specific
    bool halfResolution = true;       // Each eye gets half horizontal resolution
    bool swapEyes = false;            // Swap left/right for cross-eyed viewing
    
    // Quality
    float renderScale = 1.0f;         // Render resolution scale (0.5-2.0)
    int msaaSamples = 4;              // MSAA samples for stereo rendering
};

/**
 * EngineGL33Stereo3D - Full stereoscopic 3D rendering engine
 * 
 * This implements proper stereo rendering with:
 * - Off-axis projection matrices for true 3D
 * - Proper camera offset using the "toe-in" method
 * - Side-by-side output for 3D TVs
 * - Hardware-accelerated composition
 * - Advanced depth management
 * - Automatic convergence adjustment
 */
class EngineGL33Stereo3D
{
public:
    /**
     * Constructor
     */
    explicit EngineGL33Stereo3D(EngineGL33* parentEngine);
    
    /**
     * Destructor
     */
    ~EngineGL33Stereo3D();
    
    /**
     * Enable/disable stereo rendering
     */
    void SetEnabled(bool enabled);
    bool IsEnabled() const { return m_enabled; }
    
    /**
     * Set the stereo mode
     */
    void SetMode(Stereo3DMode mode);
    Stereo3DMode GetMode() const { return m_mode; }
    
    /**
     * Set stereo parameters
     */
    void SetParams(const Stereo3DParams& params);
    const Stereo3DParams& GetParams() const { return m_params; }
    
    /**
     * Get eye-specific view matrix (off-axis projection)
     * @param eye 0 = Left, 1 = Right
     * @param baseView Original view matrix
     * @return Modified view matrix with proper stereo offset
     */
    Matrix4 GetEyeViewMatrix(int eye, const Matrix4& baseView) const;
    
    /**
     * Get eye-specific projection matrix (off-axis)
     * @param eye 0 = Left, 1 = Right
     * @param baseProj Original projection matrix
     * @param aspect Aspect ratio of the viewport
     * @return Modified projection matrix with off-axis frustum
     */
    Matrix4 GetEyeProjection(int eye, const Matrix4& baseProj, float aspect) const;
    
    /**
     * Main render function - renders the scene in stereo
     */
    void RenderStereo(const FrameState& frame, const PassState& pass, 
                      const LightList& lights, Camera* camera);
    
    /**
     * Called at frame boundaries
     */
    void BeginFrame();
    void EndFrame();
    
    /**
     * Resize render targets when the window changes
     */
    void ResizeRenderTargets(int width, int height);
    
    /**
     * Debug functionality
     */
    void DrawDebugOverlay();
    void DrawStereoTestPattern();
    
    /**
     * Get the current eye being rendered (for shader uniforms)
     */
    int GetCurrentEye() const { return m_currentEye; }
    
    /**
     * Get stereo viewport for each eye
     */
    void GetEyeViewport(int eye, int& x, int& y, int& w, int& h) const;
    
private:
    // Parent engine reference
    EngineGL33* m_engine;
    
    // State
    bool m_enabled;
    bool m_initialized;
    Stereo3DMode m_mode;
    Stereo3DParams m_params;
    int m_currentEye;
    bool m_frameActive;
    
    // Render targets
    struct EyeRenderTarget
    {
        unsigned int fbo = 0;
        unsigned int colorTex = 0;
        unsigned int depthTex = 0;
        unsigned int colorRb = 0;
        unsigned int depthRb = 0;
        int width = 0;
        int height = 0;
    };
    
    EyeRenderTarget m_leftEye;
    EyeRenderTarget m_rightEye;
    EyeRenderTarget m_compositeTarget;
    
    // Stereo render texture arrays (for efficient dual rendering)
    unsigned int m_stereoTextureArray = 0;
    unsigned int m_stereoDepthArray = 0;
    unsigned int m_stereoFBO = 0;
    
    // Composition FBO
    unsigned m_compositeFBO = 0;
    unsigned int m_compositeTexture = 0;
    
    // Screen quad geometry
    unsigned int m_quadVAO = 0;
    unsigned int m_quadVBO = 0;
    unsigned int m_quadEBO = 0;
    
    // Shader programs
    unsigned int m_stereoComposeShader = 0;
    unsigned int m_stereoTestShader = 0;
    unsigned int m_depthVisualizerShader = 0;
    
    // Stereo rendering state
    Matrix4 m_leftView;
    Matrix4 m_rightView;
    Matrix4 m_leftProj;
    Matrix4 m_rightProj;
    float m_eyeOffset;
    
    // Frame statistics
    int m_frameCount;
    float m_averageRenderTime;
    int m_renderedEyesThisFrame;
    
    // Internal methods
    bool InitializeRenderTargets();
    void DestroyRenderTargets();
    bool InitializeCompositionShader();
    void DestroyCompositionShader();
    bool InitializeScreenQuad();
    void DestroyScreenQuad();
    
    // Rendering methods
    void RenderSceneForEye(int eye, const FrameState& frame, const PassState& pass,
                          const LightList& lights, Camera* camera);
    void RenderSceneForEyeImpl(int eye, const FrameState& frame, const PassState& pass,
                              const LightList& lights, Camera* camera);
    
    // Composition methods
    void ComposeSideBySide();
    void ComposeTopBottom();
    void ComposeAnaglyph();
    void ComposeFramePacking();
    
    // Helper methods
    void CalculateEyeMatrices(Camera* camera, float aspect);
    void DrawFullScreenQuad(unsigned int shader);
    void BindEyeTarget(int eye);
    void UnbindEyeTarget();
    void CopyDepthBuffer(int sourceEye, int destEye);
    
    // Off-axis projection helper
    Matrix4 CreateOffAxisProjection(const Matrix4& baseProj, 
                                   float left, float right, 
                                   float bottom, float top) const;
    
    // Auto-convergence
    void UpdateAutoConvergence(const FrameState& frame);
    float m_targetConvergence;
    float m_currentConvergence;
    
    // Debug
    void DrawDepthVisualization();
};

#endif // __ENGINE_GL33_STEREO3D_HPP