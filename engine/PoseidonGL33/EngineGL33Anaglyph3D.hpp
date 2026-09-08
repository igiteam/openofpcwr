#ifdef _MSC_VER
#pragma once
#endif

#ifndef __ENGINE_GL33_ANAGLYPH3D_HPP
#define __ENGINE_GL33_ANAGLYPH3D_HPP

#include <Poseidon/Core/Types.hpp>
#include <Poseidon/Math/Matrix4.hpp>
#include <Poseidon/Math/Vector3.hpp>

// Forward declarations to avoid heavy includes
class EngineGL33;
struct FrameState;
struct PassState;

/**
 * 3D Stereoscopic rendering modes
 */
enum class StereoMode
{
    Disabled = 0,      // Normal 2D rendering
    Anaglyph,          // Red-Cyan glasses (classic)
    SideBySide,        // Side-by-side for 3D TVs (Panavision)
    TopBottom,         // Top-bottom for 3D projectors
    Interleaved,       // Checkerboard/frame-sequential
};

/**
 * Anaglyph color mappings - different color channels for different glasses
 */
enum class AnaglyphColor
{
    RedCyan,      // Standard - Red left, Cyan right
    GreenMagenta, // Green left, Magenta right
    AmberBlue,    // Amber left, Blue right
    RedBlue,      // Red left, Blue right (less common)
};

/**
 * Camera offset configuration for stereoscopic rendering
 */
struct StereoParams
{
    float eyeSeparation = 0.1f;     // Distance between eyes in world units
    float convergence = 1.0f;       // Convergence plane distance (1.0 = infinity)
    float focalDistance = 50.0f;    // Focal point distance for depth scaling
    float parallaxStrength = 1.0f;  // Overall depth effect strength (0.0-2.0)
    
    // Anaglyph specific
    AnaglyphColor colorScheme = AnaglyphColor::RedCyan;
    float brightness = 1.0f;        // Overall brightness boost
    
    // Side-by-side specific
    bool halfResolution = true;     // Use half-width for each eye
    bool useHDMI3DFramePacking = false; // For HDMI 1.4a frame-packing
};

/**
 * EngineGL33Anaglyph3D - Stereoscopic 3D rendering extension for GL33 backend
 * 
 * This class manages the rendering of stereo content using various 3D formats:
 * - Anaglyph (Red-Cyan glasses)
 * - Side-by-side (3D TVs like Panavision)
 * - Top-bottom (3D projectors)
 * - Interleaved/sequential (passive 3D displays)
 */
class EngineGL33Anaglyph3D
{
public:
    /**
     * Constructor - requires the parent engine instance
     */
    explicit EngineGL33Anaglyph3D(EngineGL33* parentEngine);
    
    /**
     * Destructor - cleans up GPU resources
     */
    ~EngineGL33Anaglyph3D();
    
    /**
     * Enable/disable stereoscopic rendering
     */
    void SetEnabled(bool enabled);
    bool IsEnabled() const { return m_enabled; }
    
    /**
     * Set the rendering mode for 3D output
     */
    void SetMode(StereoMode mode);
    StereoMode GetMode() const { return m_mode; }
    
    /**
     * Access and modify stereo parameters
     */
    void SetParams(const StereoParams& params);
    const StereoParams& GetParams() const { return m_params; }
    
    /**
     * Get the offset view matrix for a specific eye
     * @param eye 0 = Left, 1 = Right
     * @param baseView The original view matrix
     * @return Modified view matrix for the specified eye
     */
    Matrix4 GetEyeViewMatrix(int eye, const Matrix4& baseView) const;
    
    /**
     * Get the offset projection matrix for a specific eye
     * @param eye 0 = Left, 1 = Right
     * @param baseProj The original projection matrix
     * @return Modified projection matrix for the specified eye
     */
    Matrix4 GetEyeProjection(int eye, const Matrix4& baseProj) const;
    
    /**
     * Main render function - called by EngineGL33
     * This handles the full stereo rendering pipeline
     */
    void RenderStereo(const FrameState& frame, const PassState& pass);
    
    /**
     * Called at the start of a frame to setup stereo rendering
     */
    void BeginFrame();
    
    /**
     * Called at the end of a frame to cleanup/composite
     */
    void EndFrame();
    
    /**
     * Quick test function - renders a simple test pattern in 3D
     * Used to verify the stereo system is working
     */
    void DrawTestPattern3D();
    
    // Debug helper - show status overlay
    void DrawDebugOverlay();
    
private:
    // Parent engine reference
    EngineGL33* m_engine;
    
    // State
    bool m_enabled;
    bool m_initialized;
    StereoMode m_mode;
    StereoParams m_params;
    
    // Frame rendering state
    bool m_frameActive;
    int m_currentEye;  // 0 = Left, 1 = Right
    
    // Offscreen render targets for stereo composition
    // Left eye render target
    unsigned int m_leftFbo = 0;
    unsigned int m_leftColorTex = 0;
    unsigned int m_leftDepthRb = 0;
    
    // Right eye render target
    unsigned int m_rightFbo = 0;
    unsigned int m_rightColorTex = 0;
    unsigned int m_rightDepthRb = 0;
    
    // Final composition FBO
    unsigned int m_composeFbo = 0;
    unsigned int m_composeTex = 0;
    
    // Screen-space quad VBO/VAO for compositing
    unsigned int m_quadVAO = 0;
    unsigned int m_quadVBO = 0;
    
    // Shader programs
    unsigned int m_anaglyphShader = 0;
    unsigned int m_sideBySideShader = 0;
    unsigned int m_topBottomShader = 0;
    
    // Status
    int m_renderWidth;
    int m_renderHeight;
    int m_compositeWidth;
    int m_compositeHeight;
    
    // Internal methods
    bool InitializeRenderTargets();
    void DestroyRenderTargets();
    bool InitializeCompositionShaders();
    void DestroyCompositionShaders();
    bool InitializeScreenQuad();
    void DestroyScreenQuad();
    
    // Composition methods
    void ComposeAnaglyph();
    void ComposeSideBySide();
    void ComposeTopBottom();
    void ComposeInterleaved();
    
    // Helper methods
    void RenderSceneForEye(int eye, const FrameState& frame, const PassState& pass);
    Vector3 GetEyeOffset(int eye) const;
    void DrawFullScreenQuad(unsigned int shader);
    
    // Apply stereo parameters to view/projection
    void ApplyStereoView(Matrix4& view, int eye) const;
    void ApplyStereoProjection(Matrix4& proj, int eye) const;
};

#endif // __ENGINE_GL33_ANAGLYPH3D_HPP