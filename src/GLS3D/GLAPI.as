/*
 Copyright (c) 2012, Adobe Systems Incorporated
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are
 met:

 * Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.

 * Neither the name of Adobe Systems Incorporated nor the names of its
 contributors may be used to endorse or promote products derived from
 this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

package GLS3D {

import flash.display.*;
import flash.display3D.*;
import flash.display3D.textures.*;
import flash.geom.*;
import flash.system.Capabilities;
import flash.utils.*;

import com.adobe.flascc.CModule;
import com.adobe.utils.v3.*;

// Linker trickery
[Csym("D", "___libgl_abc__", ".data")]

public class GLAPI {
    include 'libGLconsts.as';

    private static var _instance:GLAPI;

    public var disableCulling:Boolean = false;
    public var disableBlending:Boolean = false;
    public var log:Object = null;
    public var log2:Object = null;
    public var context:Context3D;
    public var viewportDelegator:Function;

    static private const consts:Vector.<Number> = new <Number>[0.0, 0.5, 1.0, 2.0];
    static private const zeroes:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];

    // bit 0 = whether textures are enabled
    private const ENABLE_TEXTURE_OFFSET:uint = 0;
    // bits 1-6 = whether clip planes 0-5 are enabled
    private const ENABLE_CLIPPLANE_OFFSET:uint = 1;
    // bit 7 = whether color material is enabled
    private const ENABLE_COLOR_MATERIAL_OFFSET:uint = 7;
    // bit 8 = whether lighting is enabled
    private const ENABLE_LIGHTING_OFFSET:uint = 8;
    // bit 9-16 = whether lights 0-7 are enabled
    private const ENABLE_LIGHT_OFFSET:uint = 9;
    // bit 17 = whether specular is separate
    private const ENABLE_SEPSPEC_OFFSET:uint = 17;
    // bit 18 = whether polygon offset is enabled
    private const ENABLE_POLYGON_OFFSET:uint = 18;

    private var _stage:Stage;
    private var _agalVersion:uint;
    private var _glLimits:Dictionary = new Dictionary();
    private var _driverAPI:String;
    private var _profileIndex:int;
    private var _playerVersionNumber:Vector.<int> = new <int>[0, 0, 0, 0];
    private var _glExtensions:String;

    private var _scissorRect:Rectangle;
    private var _contextEnableScissor:Boolean = false;
    private var _fixedFunctionPrograms:Dictionary = new Dictionary();
    private var _contextDepthFunction:String = Context3DCompareMode.LESS;
    private var _reusableCommandList:CommandList = new CommandList();
    private var _immediateVertexBuffers:VertexBufferPool = new VertexBufferPool();
    private var _sharedIndexBuffers:Dictionary = new Dictionary();
    private var _contextColor:Vector.<Number> = new <Number>[1, 1, 1, 1];
    private var _frontFaceClockWise:Boolean = false; // we default to CCW
    private var _glCullMode:uint = GL_BACK;
    private var _lightingStates:Vector.<LightingState> = new Vector.<LightingState>();

    private var _activeTexture:TextureInstance;
    private var _textures:Dictionary = new Dictionary();
    private var _texID:uint = 1; // so we have 0 as non-valid id
    private var NULL_TEXTURE:TextureBase = null;

    private var _activeFramebuffer:FramebufferInstance;
    private var _framebuffers:Dictionary = new Dictionary();
    private var _framebufferID:uint = 1;

    private var _activeRenderbuffer:RenderbufferInstance;
    private var _renderbuffers:Dictionary = new Dictionary();
    private var _renderbufferID:uint = 1;

    private var _shaders:Dictionary = new Dictionary();
    private var _shaderID:uint = 1;

    private var _programs:Dictionary = new Dictionary();
    private var _programID:uint = 1;
    private var _activeProgramInstance:ProgramInstance = null;

    private var _variableHandles:Dictionary = new Dictionary();
    private var _variableID:uint = 1;

    private var _buffers:Dictionary = new Dictionary();
    private var _bufferID:uint = 1;
    private var _activeArrayBuffer:BufferInstance = null;
    private var _activeElementArrayBuffer:BufferInstance = null;

    private var _shininessVec:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];
    private var _globalAmbient:Vector.<Number> = new <Number>[0.2, 0.2, 0.2, 1];
    private var _polygonOffsetValue:Number = -0.0005;
    private var _lights:Vector.<Light> = new Vector.<Light>(8);
    private var _lightsEnabled:Vector.<Boolean> = new Vector.<Boolean>(8);
    private var _enableTexGenS:Boolean = false;
    private var _enableTexGenT:Boolean = false;
    private var _texGenParamS:uint = GL_SPHERE_MAP;
    private var _texGenParamT:uint = GL_SPHERE_MAP;
    private var _contextWidth:int = 0;
    private var _contextHeight:int = 0;
    private var _contextClearR:Number;
    private var _contextClearG:Number;
    private var _contextClearB:Number;
    private var _contextClearA:Number;
    private var _contextClearDepth:Number = 1.0;
    private var _contextClearStencil:uint = 0;
    private var _contextClearMask:uint;
    private var _contextEnableStencil:Boolean = false;
    private var _contextEnableAlphaTest:Boolean = false;
    private var _contextStencilActionStencilFail:String = Context3DStencilAction.KEEP;
    private var _contextStencilActionDepthFail:String = Context3DStencilAction.KEEP;
    private var _contextStencilActionPass:String = Context3DStencilAction.KEEP;
    private var _contextStencilCompareMode:String = Context3DCompareMode.ALWAYS;
    private var _contextEnableDepth:Boolean = true;
    private var _contextDepthMask:Boolean = true;
    private var _contextSrcBlendFunc:String = Context3DBlendFactor.ZERO;
    private var _contextDstBlendFunc:String = Context3DBlendFactor.ONE;
    private var _contextEnableCulling:Boolean;
    private var _contextEnableBlending:Boolean;
    private var _contextEnableTextures:Vector.<Boolean> = new Vector.<Boolean>(8);
    private var _contextEnableLighting:Boolean = false;
    private var _contextColorMaterial:Boolean = false;
    private var _contextSeparateSpecular:Boolean = false;
    private var _contextEnablePolygonOffset:Boolean = false;
    private var _activeCommandList:CommandList = null;
    private var _commandLists:Vector.<CommandList> = null;
    private var _activeTextureUnit:uint = 0;
    private var _textureSamplers:Vector.<TextureInstance> = new Vector.<TextureInstance>(8);
    private var _textureSamplerIDs:Vector.<uint> = new Vector.<uint>(8);
    private var _offsetFactor:Number = 0.0;
    private var _offsetUnits:Number = 0.0;
    private var _glStateFlags:uint = 0;
    private var _clipPlanes:Vector.<Number> = new Vector.<Number>(6 * 4);    // space for 6 clip planes
    private var _clipPlaneEnabled:Vector.<Boolean> = new Vector.<Boolean>(8); // defaults to false
    private var _modelViewStack:Vector.<Matrix3D> = new <Matrix3D>[new Matrix3D()];
    private var _projectionStack:Vector.<Matrix3D> = new <Matrix3D>[new Matrix3D()];
    private var _textureStack:Vector.<Matrix3D> = new <Matrix3D>[new Matrix3D()];
    private var _currentMatrixStack:Vector.<Matrix3D> = _modelViewStack;
    private var _contextMaterial:Material = new Material(true);
    private var _cubeVertexData:Vector.<Number>;
    private var _cubeVertexBuffer:VertexBuffer3D = null;
    private var _agalAssembler:AGALMiniAssembler = null;

    [Autowire]
    public static function init(context:Context3D, stage:Stage, log:Object = null, log2:Object = null, useAgalVersion:uint = 0):void {
        _instance = new GLAPI(context, stage, log, log2, useAgalVersion);
        (log || log2 || {send: trace}).send("GLAPI initialized.");
    }

    [Inline]
    public static function get instance():GLAPI {
        if (!_instance)
            throw new Error("Instance is null, did you forget calling GLAPI.init() in AlcConsole.as?");
        return _instance;
    }

    [Inline]
    final public function get agalVersion():uint {
        return _agalVersion;
    }

    [Inline]
    public function send(value:String):void {
        if (log)
            log.send(value)
    }

    [Ignore]
    final private function matrix3DToString(m:Matrix3D):String {
        var data:Vector.<Number> = m.rawData;
        return ("[ " + data[0].toFixed(3) + ", " + data[4].toFixed(3) + ", " + data[8].toFixed(3) + ", " + data[12].toFixed(3) + " ]\n" +
        "[ " + data[1].toFixed(3) + ", " + data[5].toFixed(3) + ", " + data[9].toFixed(3) + ", " + data[13].toFixed(3) + " ]\n" +
        "[ " + data[2].toFixed(3) + ", " + data[6].toFixed(3) + ", " + data[10].toFixed(3) + ", " + data[14].toFixed(3) + " ]\n" +
        "[ " + data[3].toFixed(3) + ", " + data[7].toFixed(3) + ", " + data[11].toFixed(3) + ", " + data[15].toFixed(3) + " ]");
    }

    // ======================================================================
    //  Polygon Offset
    // ----------------------------------------------------------------------

    [Internal]
    public function glPolygonMode(face:uint, mode:uint):void {
        switch (mode) {
            case GL_POINT:
                CONFIG::debug {
                    if (log) log.send("glPolygonMode GL_POINT not yet implemented, mode is always GL_FILL.");
                }
                break;
            case GL_LINE:
                CONFIG::debug {
                    if (log) log.send("glPolygonMode GL_LINE not yet implemented, mode is always GL_FILL.");
                }
                break;
            default:
                // GL_FILL!
        }
        void(face);
    }

    [Internal]
    public function glPolygonOffset(factor:Number, units:Number):void {
        this._offsetFactor = factor;
        this._offsetUnits = units;
        //if (log) log.send("glPolygonOffset() called with (" + factor + ", " + units + ")")
        CONFIG::debug {
            if (log) log.send("[ERROR] glPolygonOffset() not yet implemented.");
        }
    }

    [Internal]
    public function glShadeModel(mode:uint):void {
        switch (mode) {
            case GL_FLAT:
                CONFIG::debug {
                    if (log) log.send("[WARNING] glShadeModel GL_FLAT not yet implemented, mode is always GL_SMOOTH.");
                }
                break;
            default:
                // GL_SMOOTH! Stage3D by default.
        }
    }

    // ======================================================================
    //  Alpha Testing
    // ----------------------------------------------------------------------

    [Internal]
    public function glAlphaFunc(func:uint, ref:Number):void {
        //TODO: glAlphaFunc
        CONFIG::debug {
            if (log) log.send("[WARNING] glAlphaFunc() not yet implemented.");
            void(func);
            void(ref);
        }
    }

    [Inline]
    private static function setVector(vec:Vector.<Number>, x:Number, y:Number, z:Number, w:Number):void {
        vec[0] = x;
        vec[1] = y;
        vec[2] = z;
        vec[3] = w;
    }

    [Inline]
    private static function copyVector(dest:Vector.<Number>, src:Vector.<Number>):void {
        dest[0] = src[0];
        dest[1] = src[1];
        dest[2] = src[2];
        dest[3] = src[3];
    }

    [Internal]
    public function glMaterial(face:uint, pname:uint, r:Number, g:Number, b:Number, a:Number):void {
        // if pname == GL_SPECULAR, then "r" is shininess.
        // FIXME (klin): Ignore face for now. Always GL_FRONT_AND_BACK
        var material:Material;

        if (this._activeCommandList) {
            var activeState:ContextState = this._activeCommandList.ensureActiveState();
            void(activeState);
            material = this._activeCommandList.activeState.material;
        }
        else {
            material = this._contextMaterial;
        }


        switch (pname) {
            case GL_AMBIENT:
                if (!material.ambient)
                    material.ambient = new <Number>[r, g, b, a];
                else
                    setVector(material.ambient, r, g, b, a);
                break;
            case GL_DIFFUSE:
                if (!material.diffuse)
                    material.diffuse = new <Number>[r, g, b, a];
                else
                    setVector(material.diffuse, r, g, b, a);
                break;
            case GL_AMBIENT_AND_DIFFUSE:
                if (!material.ambient)
                    material.ambient = new <Number>[r, g, b, a];
                else
                    setVector(material.ambient, r, g, b, a);

                if (!material.diffuse)
                    material.diffuse = new <Number>[r, g, b, a];
                else
                    setVector(material.diffuse, r, g, b, a);
                break;
            case GL_SPECULAR:
                if (!material.specular)
                    material.specular = new <Number>[r, g, b, a];
                else
                    setVector(material.specular, r, g, b, a);
                break;
            case GL_SHININESS:
                material.shininess = r;
                break;
            case GL_EMISSION:
                if (!material.emission)
                    material.emission = new <Number>[r, g, b, a];
                else
                    setVector(material.emission, r, g, b, a);
                break;
            default:
                if (log) log.send("[NOTE] Unsupported glMaterial call with 0x" + pname.toString(16));
        }
    }

    [Internal]
    public function glLightModeli(pname:uint, param:int):void {
        switch (pname) {
            case GL_LIGHT_MODEL_COLOR_CONTROL:
                _contextSeparateSpecular = (param == GL_SEPARATE_SPECULAR_COLOR);
                if (_contextSeparateSpecular)
                    setGLState(ENABLE_SEPSPEC_OFFSET);
                else
                    clearGLState(ENABLE_SEPSPEC_OFFSET);
                break;

                // unsupported for now
            case GL_LIGHT_MODEL_TWO_SIDE:
            case GL_LIGHT_MODEL_AMBIENT:
            case GL_LIGHT_MODEL_LOCAL_VIEWER:
            default:
                break;
        }

        CONFIG::debug {
            if (log) log.send("glLightModeli() not yet implemented");
        }
    }

    [Internal]
    public function glLight(light:uint, pname:uint, r:Number, g:Number, b:Number, a:Number):void {
        var lightIndex:int = light - GL_LIGHT0;
        if (lightIndex < 0 || lightIndex > 7) {
            CONFIG::debug {
                if (log) log.send("glLight(): light index " + lightIndex + " out of bounds");
            }
            return;
        }

        var l:Light = _lights[lightIndex];
        if (!l)
            l = _lights[lightIndex] = new Light(true, lightIndex == 0);

        switch (pname) {
            case GL_AMBIENT:
                l.ambient[0] = r;
                l.ambient[1] = g;
                l.ambient[2] = b;
                l.ambient[3] = a;
                break;
            case GL_DIFFUSE:
                l.diffuse[0] = r;
                l.diffuse[1] = g;
                l.diffuse[2] = b;
                l.diffuse[3] = a;
                break;
            case GL_SPECULAR:
                l.specular[0] = r;
                l.specular[1] = g;
                l.specular[2] = b;
                l.specular[3] = a;
                break;
            case GL_POSITION:
                // transform position to eye-space before storing.
                var m:Matrix3D = _modelViewStack[_modelViewStack.length - 1].clone();
                var result:Vector3D;
                if (a == 0.0) {	// Directional light
                    m.position = new Vector3D(0, 0, 0, 1);
                    result = m.transformVector(new Vector3D(r, g, b, a));
                    l.position[0] = result.x;
                    l.position[1] = result.y;
                    l.position[2] = result.z;
                    l.position[3] = 0;

                    l.type = Light.LIGHT_TYPE_DIRECTIONAL;
                }
                else {	// Point light
                    result = m.transformVector(new Vector3D(r, g, b, a));
                    l.position[0] = result.x;
                    l.position[1] = result.y;
                    l.position[2] = result.z;
                    l.position[3] = result.w;

                    l.type = Light.LIGHT_TYPE_POINT;
                }
                break;
            default:
                break;
        }
    }

    [Internal]
    public function glGetString(pname:int):String {
        CONFIG::debug {
            if (log) log.send("glGetString 0x" + pname.toString(16));
        }

        switch (pname) {
            case GL_VENDOR:
                return "Adobe";
            case GL_RENDERER:
                return "Stage3D/" + this._driverAPI;
            case GL_VERSION:
                return "2.1";
            case GL_SHADING_LANGUAGE_VERSION:
                if (this._profileIndex > 4)
                    return "1.50";
                else if (this._profileIndex == 4)
                    return "1.30";
                return "1.20";
            case GL_EXTENSIONS:
                return this._glExtensions;
        }
        return null;
    }

    [Internal]
    public function glGetIntegerv(pname:uint, buf:ByteArray, offset:uint):void {
        CONFIG::debug {
            if (log) log.send("glGetIntegerv 0x" + pname.toString(16));
        }

        if (pname in _glLimits) {
            buf.position = offset;
            buf.writeInt(_glLimits[pname]);
            return;
        }

        switch (pname) {
            case GL_VIEWPORT:
                buf.position = offset + 0;
                buf.writeInt(0); // x
                buf.position = offset + 4;
                buf.writeInt(0); // y
                buf.position = offset + 8;
                buf.writeInt(_contextWidth); // width
                buf.position = offset + 12;
                buf.writeInt(_contextHeight); // height
                break;
            default:
                buf.position = offset + 0;
                buf.writeInt(0);
                if (log) log.send("[ERROR] Unsupported glGetIntegerv call with 0x" + pname.toString(16));
        }
    }

    [Internal]
    public function glGetFloatv(pname:uint, buf:ByteArray, offset:uint):void {
        CONFIG::debug {
            if (log) log.send("glGetFloatv 0x" + pname.toString(16));
        }

        switch (pname) {
            case GL_MODELVIEW_MATRIX:
                var v:Vector.<Number> = new Vector.<Number>(16);
                _modelViewStack[_modelViewStack.length - 1].copyRawDataTo(v);
                buf.position = offset;
                for (var i:int = 0; i < 16; i++)
                    buf.writeFloat(v[i]);
                break;
            default:
                if (log) log.send("[ERROR] Unsupported glGetFloatv call with 0x" + pname.toString(16));
        }
    }

    [Internal]
    public function glClipPlane(plane:uint, a:Number, b:Number, c:Number, d:Number):void {
        CONFIG::debug {
            if (log) log.send("[NOTE] glClipPlane called for plane 0x" + plane.toString(16) + ", with args " + a + ", " + b + ", " + c + ", " + d);
        }

        var index:int = plane - GL_CLIP_PLANE0;

        // Convert coordinates to eye space (modelView) before storing
        var m:Matrix3D = _modelViewStack[_modelViewStack.length - 1].clone();
        m.invert();
        m.transpose();
        var result:Vector3D = m.transformVector(new Vector3D(a, b, c, d));

        _clipPlanes[index * 4 + 0] = result.x;
        _clipPlanes[index * 4 + 1] = result.y;
        _clipPlanes[index * 4 + 2] = result.z;
        _clipPlanes[index * 4 + 3] = a * m.rawData[3] + b * m.rawData[7] + c * m.rawData[11] + d * m.rawData[15]; //result.w
    }

    [Deprecated]
    private function executeCommandList(cl:CommandList):void {
        // FIXME (egeorgire): do this on-deamnd?
        // Pre-calculate matrix
        var m:Matrix3D = _modelViewStack[_modelViewStack.length - 1].clone();
        var p:Matrix3D = _projectionStack[_projectionStack.length - 1].clone();
        var t:Matrix3D = _textureStack[_textureStack.length - 1].clone();
        //m.append(p)


        p.prepend(m);
        var invM:Matrix3D = m.clone();
        invM.invert();
        var modelToClipSpace:Matrix3D = p;

        if (isGLState(ENABLE_POLYGON_OFFSET)) {
            // Adjust the projection matrix to give us z offset
            CONFIG::debug {
                if (log) log.send("Applying polygon offset");
            }

            modelToClipSpace = p.clone();
            modelToClipSpace.appendTranslation(0, 0, _polygonOffsetValue);
        }


        // Current active textures ??
        var ti:TextureInstance;
        var i:int = _activeTextureUnit;
        /* for (i = 0; i < 1; i++ ) */
        /* { */
        ti = _textureSamplers[i];
        if (ti && _contextEnableTextures[i]) {
            this.context.setTextureAt(i, ti.boundType == GL_TEXTURE_2D ? ti.texture : ti.cubeTexture);
            CONFIG::debug {
                if (log) log.send("setTexture " + i + " -> " + ti.texID);
            }
        }
        else {
            this.context.setTextureAt(i, null);
            CONFIG::debug {
                if (log) log.send("setTexture " + i + " -> 0");
            }
        }
        /* } */

        var textureStatInvalid:Boolean = false;
        const count:int = cl.commands.length;
        var command:Object;
        for (var k:int = 0; k < count; k++) {
            command = cl.commands[k];
            var stateChange:ContextState = command as ContextState;
            if (stateChange) {

                // We execute state changes before stream changes, so
                // we must have a state change

                // Execute state changes
                /* if (contextEnableTextures && stateChange.textureSamplers) */
                if (stateChange.textureSamplers) {
                    for (i = 0; i < _contextEnableTextures.length; i++) {
                        var texID:int = stateChange.textureSamplers[i];
                        if (texID != -1) {
                            CONFIG::debug {
                                if (log) log.send("Mapping texture " + texID + " to sampler " + i);
                            }
                            ti = (texID != 0) ? _textures[texID] : null;
                            _textureSamplers[i] = ti;
                            if (i == _activeTextureUnit)
                                _activeTexture = ti; // Executing the glBind, so that after running through the list we have the side-effect correctly
                            textureStatInvalid = true;
                            if (ti)
                                this.context.setTextureAt(i, ti.boundType == GL_TEXTURE_2D ? ti.texture : ti.cubeTexture);
                            else
                                this.context.setTextureAt(i, null);
                            CONFIG::debug {
                                if (log) log.send("setTexture " + i + " -> " + (ti ? ti.texID : 0));
                            }
                        }
                    }
                }

                var stateMaterial:Material = stateChange.material;
                if (stateMaterial) {
                    if (stateMaterial.ambient)
                        copyVector(_contextMaterial.ambient, stateMaterial.ambient);
                    if (stateMaterial.diffuse)
                        copyVector(_contextMaterial.diffuse, stateMaterial.diffuse);
                    if (stateMaterial.specular)
                        copyVector(_contextMaterial.specular, stateMaterial.specular);
                    if (!isNaN(stateMaterial.shininess))
                        _contextMaterial.shininess = stateMaterial.shininess;
                    if (stateMaterial.emission)
                        copyVector(_contextMaterial.emission, stateMaterial.emission);
                }
            }

            var stream:VertexStream = command as VertexStream;
            if (stream) {

                // Make sure we have the right program, and see if we need to updated it if some state change requires it
                ensureProgramUpToDate(stream);

                // If the program has no textures, then disable them all:
                if (!stream.program.hasTexture) {
                    for (i = 0; i < 8; i++) {
                        this.context.setTextureAt(i, null);
                        CONFIG::debug {
                            if (log) log.send("setTexture " + i + " -> 0");
                        }
                    }
                }

                context.setProgram(stream.program.program);

                // FIXME (egeorgie): do we need to do this after setting every program, or just once after we calculate the matrix?
                if (stream.polygonOffset) {
                    // Adjust the projection matrix to give us z offset
                    CONFIG::debug {
                        if (log) log.send("Applying polygon offset, recorded in the list");
                    }
                    modelToClipSpace = p.clone();
                    modelToClipSpace.appendTranslation(0, 0, _polygonOffsetValue);
                }
                context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 0, modelToClipSpace, true);
                if (stream.polygonOffset) {
                    // Restore
                    modelToClipSpace = p;
                }
                context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 4, m, true);
                context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 8, invM, true);
                context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 12, t, true);
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 16, consts);
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 17, _contextColor);

                // Upload the clip planes
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 18, _clipPlanes, 6);

                // Zero-out the ones that are not enabled
                for (i = 0; i < 6; i++) {
                    if (!_clipPlaneEnabled[i])
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 18 + i, zeroes, 1);
                }

                // Calculate origin of eye-space
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 24, new <Number>[0, 0, 0, 1], 1);

                // Upload material components
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 25, _contextMaterial.ambient, 1);
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 26, _contextMaterial.diffuse, 1);
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 27, _contextMaterial.specular, 1);
                _shininessVec[0] = _contextMaterial.shininess;
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 28, _shininessVec, 1);
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 29, _contextMaterial.emission, 1);

                // Upload lights
                // FIXME (klin): will be per light...for now, fake a light and assume local viewer.
                // default global light:
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 30, _globalAmbient, 1);

                // light constants
                for (i = 0; i < 8; i++) {
                    var index:int = 31 + i * 4;
                    if (_lightsEnabled[i]) {
                        var l:Light = _lights[i];
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, index, l.position, 1);
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, index + 1, l.ambient, 1);
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, index + 2, l.diffuse, 1);
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, index + 3, l.specular, 1);
                    }
                    else {
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, index, zeroes, 1);
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, index + 1, zeroes, 1);
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, index + 2, zeroes, 1);
                        context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, index + 3, zeroes, 1);
                    }

                }

                // Map the Vertex buffer

                // position
                context.setVertexBufferAt(0, stream.vertexBuffer, 0 /*bufferOffset*/, Context3DVertexBufferFormat.FLOAT_3);

                // color
                if (0 != (stream.program.vertexStreamUsageFlags & VertexBufferBuilder.HAS_COLOR))
                    context.setVertexBufferAt(1, stream.vertexBuffer, 3 /*bufferOffset*/, Context3DVertexBufferFormat.FLOAT_4);
                else
                    context.setVertexBufferAt(1, null);

                // normal
                if (0 != (stream.program.vertexStreamUsageFlags & VertexBufferBuilder.HAS_NORMAL))
                    context.setVertexBufferAt(2, stream.vertexBuffer, 7 /*bufferOffset*/, Context3DVertexBufferFormat.FLOAT_3);
                else
                    context.setVertexBufferAt(2, null);

                // texture coords
                if (0 != (stream.program.vertexStreamUsageFlags & VertexBufferBuilder.HAS_TEXTURE2D))
                    context.setVertexBufferAt(3, stream.vertexBuffer, 10 /*bufferOffset*/, Context3DVertexBufferFormat.FLOAT_2);
                else
                    context.setVertexBufferAt(3, null);

                context.drawTriangles(stream.indexBuffer);

                // If we're executing on compilation, this may be an immediate command stream, so update the pool
                if (cl.executeOnCompile)
                    _immediateVertexBuffers.markInUse(stream.vertexBuffer);
            }
        }
    }

    [Internal]
    public function glGenLists(count:uint):uint {
        CONFIG::debug {
            if (log) log.send("glGenLists " + count);
        }

        if (!_commandLists)
            _commandLists = new Vector.<CommandList>();

        var oldLength:int = _commandLists.length;
        _commandLists.length = oldLength + count;
        return oldLength;
    }

    [Internal]
    public function glMatrixMode(mode:uint):void {
        CONFIG::debug {
            if (log) log.send("glMatrixMode \nSwitch stack to " + MATRIX_MODE[mode - GL_MODELVIEW]);
        }

        switch (mode) {
            case GL_MODELVIEW:
                _currentMatrixStack = _modelViewStack;
                break;

            case GL_PROJECTION:
                _currentMatrixStack = _projectionStack;
                break;

            case GL_TEXTURE:
                _currentMatrixStack = _textureStack;
                break;

            default:
                if (log) log.send("[ERROR] Unknown Matrix Mode 0x" + mode.toString());
        }
    }

    [Internal]
    public function glPushMatrix():void {
        CONFIG::debug {
            if (log) log.send("glPushMatrix");
        }
        _currentMatrixStack.push(_currentMatrixStack[_currentMatrixStack.length - 1].clone());
    }

    [Internal]
    public function glPopMatrix():void {
        CONFIG::debug {
            if (log) log.send("glPopMatrix");
        }
        _currentMatrixStack.pop();
        if (_currentMatrixStack.length == 0) {
            if (log) log.send("[ERROR] marix stack underflow!");
            _currentMatrixStack.push(new Matrix3D());
        }
    }

    [Internal]
    public function glLoadIdentity():void {
        CONFIG::debug {
            if (log) log.send("glLoadIdentity");
        }
        _currentMatrixStack[_currentMatrixStack.length - 1].identity();
    }

    [Internal]
    public function glOrtho(left:Number, right:Number, bottom:Number, top:Number, zNear:Number, zFar:Number):void {
        CONFIG::debug {
            if (log) log.send("glOrtho: left = " + left + ", right = " + right + ", bottom = " + bottom + ", top = " + top + ", zNear = " + zNear + ", zFar = " + zFar);
        }

        var tx:Number = -(right + left) / (right - left);
        var ty:Number = -(top + bottom) / (top - bottom);
        var tz:Number = -(zFar + zNear) / (zFar - zNear);

        // in column-major order...
        var m:Matrix3D = new Matrix3D(new <Number>[
            2 / (right - left), 0, 0, 0,
            0, 2 / (top - bottom), 0, 0,
            0, 0, -2 / ( zFar - zNear), 0,
            tx, ty, tz, 1]);

        // Multiply current matrix by the ortho matrix
        _currentMatrixStack[_currentMatrixStack.length - 1].prepend(m);
    }

    [Internal]
    public function glTranslate(x:Number, y:Number, z:Number):void {
        CONFIG::debug {
            if (log) log.send("glTranslate");
        }
        _currentMatrixStack[_currentMatrixStack.length - 1].prependTranslation(x, y, z);
    }

    [Internal]
    public function glRotate(degrees:Number, x:Number, y:Number, z:Number):void {
        CONFIG::debug {
            if (log) log.send("glRotate");
        }
        _currentMatrixStack[_currentMatrixStack.length - 1].prependRotation(degrees, new Vector3D(x, y, z));
    }

    [Internal]
    public function glScale(x:Number, y:Number, z:Number):void {
        CONFIG::debug {
            if (log) log.send("glScale");
        }

        if (x != 0 && y != 0 && z != 0)
            _currentMatrixStack[_currentMatrixStack.length - 1].prependScale(x, y, z);
    }

    [Internal]
    public function glMultMatrix(ram:ByteArray, floatArray:Boolean):void {
        CONFIG::debug {
            if (log) log.send("glMultMatrix floatArray: " + floatArray.toString());
        }

        var v:Vector.<Number> = new Vector.<Number>(16);
        for (var i:int = 0; i < 16; i++)
            v[i] = floatArray ? ram.readFloat() : ram.readDouble();
        var m:Matrix3D = new Matrix3D(v);
        this._currentMatrixStack[this._currentMatrixStack.length - 1].prepend(m);
    }

    [Internal]
    public function glLoadMatrix(ram:ByteArray, floatArray:Boolean):void {
        CONFIG::debug {
            if (log) log.send("glLoadMatrix floatArray: " + floatArray.toString());
        }

        var v:Vector.<Number> = new Vector.<Number>(16);
        for (var i:int = 0; i < 16; i++)
            v[i] = floatArray ? ram.readFloat() : ram.readDouble();
        var m:Matrix3D = new Matrix3D(v);
        this._currentMatrixStack[this._currentMatrixStack.length - 1] = m;
    }

    [Internal]
    public function glDepthMask(enable:Boolean):void {
        CONFIG::debug {
            if (log) log.send("glDepthMask(" + enable + "), currently contextEnableDepth = " + _contextEnableDepth);
        }
        _contextDepthMask = enable;
        if (_contextEnableDepth) {
            context.setDepthTest(_contextDepthMask, _contextDepthFunction);
        }
    }

    [Internal]
    public function glDepthFunc(mode:uint):void {
        CONFIG::debug {
            if (log) log.send("glDepthFunc( " + COMPARE_MODE[mode - GL_NEVER] + " ), currently contextEnableDepth = " +
                    _contextEnableDepth);
        }

        _contextDepthFunction = convertCompareMode(mode);
        if (_contextEnableDepth)
            context.setDepthTest(_contextDepthMask, _contextDepthFunction);
    }

    static private function convertCompareMode(mode:uint):String {
        switch (mode) {
            case GL_NEVER:
                return Context3DCompareMode.NEVER;
            case GL_LESS:
                return Context3DCompareMode.LESS;
            case GL_EQUAL:
                return Context3DCompareMode.EQUAL;
            case GL_LEQUAL:
                return Context3DCompareMode.LESS_EQUAL;
            case GL_GREATER:
                return Context3DCompareMode.GREATER;
            case GL_NOTEQUAL:
                return Context3DCompareMode.NOT_EQUAL;
            case GL_GEQUAL:
                return Context3DCompareMode.GREATER_EQUAL;
            case GL_ALWAYS:
                return Context3DCompareMode.ALWAYS;
        }
        return null;
    }

    static private function texGenParamToString(param:uint):String {
        if (param < GL_NORMAL_MAP)
            return GL_PARAM[param - GL_EYE_LINEAR];
        else
            return GL_PARAM[param - GL_NORMAL_MAP];
    }

    [Internal]
    public function glTexGeni(coord:uint, pname:uint, param:uint):void {
        CONFIG::debug {
            if (log) log.send("glTexGeni( " + GL_COORD_NAME[coord - GL_S] + ", " + GL_PARAM_NAME[pname -
                    GL_TEXTURE_GEN_MODE] + ", " + texGenParamToString(param) + ")");
        }

        if (GL_T < coord) {
            if (log) log.send("[ERROR] Unsupported " + GL_COORD_NAME[coord - GL_S]);
            return;
        }

        if (pname != GL_TEXTURE_GEN_MODE) {
            if (log) log.send("[ERROR] Unsupported " + GL_PARAM_NAME[pname - GL_TEXTURE_GEN_MODE]);
            return;
        }

        switch (coord) {
            case GL_S:
                _texGenParamS = param;
                break;

            case GL_T:
                _texGenParamT = param;
                break;
        }
    }

    [Deprecated]
    final private function setupIndexBuffer(stream:VertexStream, mode:uint, count:int):void {
        var key:uint = ((mode << 20) | count);
        var indexBuffer:IndexBuffer3D = _sharedIndexBuffers[key];

        if (!indexBuffer) {
            var indexData:Vector.<uint> = new Vector.<uint>();
            generateDLIndexData(mode, count, indexData);
            indexBuffer = context.createIndexBuffer(indexData.length);
            indexBuffer.uploadFromVector(indexData, 0, indexData.length);

            // Cache
            _sharedIndexBuffers[key] = indexBuffer;
        }
        stream.indexBuffer = indexBuffer;
    }

    [Deprecated]
    final private function generateDLIndexData(mode:uint, count:int, indexData:Vector.<uint>):void {
        var i:int;
        var p0:int;
        var p1:int;
        var p2:int;
        var p3:int;

        switch (mode) {
            case GL_LINES:
                CONFIG::debug {
                    if (log) log.send("generateDLIndexData with GL_LINES");
                }
                /* for (i = 0; i < count; i += 1) { */
                /* indexData.push(i); */
                /* } */
                /* break; */
            case GL_QUADS:
                // Assert count == n * 4, n >= 1
                // for each group of 4 vertices 0, 1, 2, 3 draw two triangles 0, 1, 2 and 0, 2, 3

                for (i = 0; i < count; i += 4) {
                    indexData.push(i);
                    indexData.push(i + 1);
                    indexData.push(i + 2);

                    indexData.push(i);
                    indexData.push(i + 2);
                    indexData.push(i + 3);
                }
                break;

            case GL_QUAD_STRIP:
                // Assert count == n * 2, n >= 2
                // Draws a connected group of quadrilaterals. One quadrilateral is defined for each pair of vertices presented after the first pair.
                // Vertices 2n - 2, 2n - 1, 2n + 1, 2n  define a quadrilateral.

                for (i = 0; i < count - 2; i += 2) {
                    // The four corners of the quadrilateral are

                    p0 = i;
                    p1 = i + 1;
                    p2 = i + 2;
                    p3 = i + 3;

                    // Draw as two triangles 0, 1, 2 and 2, 1, 3
                    indexData.push(p0);
                    indexData.push(p1);
                    indexData.push(p2);

                    indexData.push(p2);
                    indexData.push(p1);
                    indexData.push(p3);
                }

                break;

            case GL_TRIANGLES:
                for (i = 0; i < count; i++) {
                    indexData.push(i);
                }
                break;

            case GL_TRIANGLE_STRIP:
                for (i = 0; i < count - 2; i++) {
                    p0 = i;
                    p1 = i + 1;
                    p2 = i + 2;

                    indexData.push(p0);
                    if (i % 2 == 0) {
                        indexData.push(p1);
                        indexData.push(p2);
                    }
                    else {
                        indexData.push(p2);
                        indexData.push(p1);
                    }
                }
                break;

            case GL_POLYGON:
            case GL_TRIANGLE_FAN:
                for (i = 0; i < count - 2; i++) {
                    p0 = i + 1;
                    p1 = i + 2;

                    indexData.push(0);
                    indexData.push(p0);
                    indexData.push(p1);
                }
                break;

            default:
                if (log) log.send("[ERROR] Not yet implemented mode for glBegin " + BEGIN_MODE[mode]);
                for (i = 0; i < count; i++) {
                    indexData.push(i);
                }
        }
    }

    [Internal]
    public function glGenBuffers(length:uint):uint {
        const result:uint = this._bufferID;
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glGenBuffers " + length + ", returning ID = [ " + result + ", " + (result +
                        length - 1) + " ]\n");
        }
        for (var i:int = 0; i < length; i++) {
            this._buffers[this._bufferID] = new BufferInstance(); // FIXME: Pooled BufferInstance ?
            this._buffers[this._bufferID].id = this._bufferID;
            this._bufferID++;
        }
        return result;
    }

    [Internal]
    public function glIsBuffer(id:uint):Boolean {
        if (id <= this._bufferID)
            return false;
        return (id in this._buffers);
    }

    [Internal]
    public function glBindBuffer(target:uint, buffer:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glBindBuffer target: 0x" + target.toString(16) + " buffer: " + buffer);
        }

        if (target == GL_ARRAY_BUFFER) {
            if (buffer != 0) {
                this._activeArrayBuffer = this._buffers[buffer];
                this._activeArrayBuffer.type = GL_ARRAY_BUFFER;
            }
            else {
                this._activeArrayBuffer = null;
            }
        }

        if (target == GL_ELEMENT_ARRAY_BUFFER) {
            if (buffer != 0) {
                this._activeElementArrayBuffer = this._buffers[buffer];
                this._activeElementArrayBuffer.type = GL_ELEMENT_ARRAY_BUFFER;
            }
            else {
                this._activeElementArrayBuffer = null;
            }
        }
    }

    protected function _createIndexBuffer(size:uint, usage:uint):IndexBuffer3D {
        if (this.context.createIndexBuffer.length >= 2)
            return this.context.createIndexBuffer.call(null, size / 2, usage == GL_DYNAMIC_DRAW ? "dynamicDraw" : "staticDraw");
        else
            return this.context.createIndexBuffer(size / 2);
    }

    [Internal]
    public function glBufferData(target:uint, size:uint, data:ByteArray, dataPtr:uint, usage:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glBufferData target: 0x" + target.toString(16) + " size: " + size);
        }

        if (target == GL_ARRAY_BUFFER) {
            // We can not create vertex buffer here because we don't know element size here
            this._activeArrayBuffer.size = size;
            this._activeArrayBuffer.uploaded = false;
            this._activeArrayBuffer.data = this._activeArrayBuffer.data || new ByteArray();

            if (dataPtr != 0) {
                this._activeArrayBuffer.data.position = 0;
                this._activeArrayBuffer.data.length = 0;
                this._activeArrayBuffer.data.writeBytes(data, dataPtr, size);
            }
        }

        if (target == GL_ELEMENT_ARRAY_BUFFER) {
            // In case of index bufer we can calculate number of elements from byte size
            this._activeElementArrayBuffer.size = size;
            this._activeElementArrayBuffer.uploaded = true;
            this._activeElementArrayBuffer.indexBuffer = this._createIndexBuffer(size, usage);

            if (dataPtr != 0) {
                this._activeElementArrayBuffer.indexBuffer.uploadFromByteArray(data, dataPtr, 0, size / 2);
            }
            else {
                // In case of NULL data pointer just initialize buffer with zeroes
                var tmp:ByteArray = new ByteArray();
                tmp.length = size;
                this._activeElementArrayBuffer.indexBuffer.uploadFromByteArray(tmp, 0, 0, size / 2);
            }
        }
    }

    [Internal]
    public function glBufferSubData(target:uint, size:uint, data:ByteArray, dataPtr:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glBufferSubData size: " + size + "\n");
        }

        if (target == GL_ARRAY_BUFFER) {
            if (_activeArrayBuffer.vertexBuffer) {
                _activeArrayBuffer.vertexBuffer.uploadFromByteArray(data, dataPtr, 0, size / _activeArrayBuffer.stride);
            }
            else {
                _activeArrayBuffer.uploaded = false;
                _activeArrayBuffer.data = _activeArrayBuffer.data || new ByteArray();
                if (dataPtr != 0) {
                    _activeArrayBuffer.data.position = 0;
                    _activeArrayBuffer.data.length = 0;
                    _activeArrayBuffer.data.writeBytes(data, dataPtr, size);
                }
            }
        }

        if (target == GL_ELEMENT_ARRAY_BUFFER) {
            CONFIG::debug {
                if (log2) log2.send("[IMPLEMENTED] glBufferSubData activeElementArrayBuffer: " + _activeElementArrayBuffer);
            }

            if (_activeElementArrayBuffer.indexBuffer) {
                _activeElementArrayBuffer.indexBuffer.uploadFromByteArray(data, dataPtr, 0, size / 2);
            }
            else {
                // In normal case we should never get here
                _activeElementArrayBuffer.uploaded = false;
                _activeElementArrayBuffer.data = _activeElementArrayBuffer.data || new ByteArray();
                if (dataPtr != 0) {
                    _activeElementArrayBuffer.data.position = 0;
                    _activeElementArrayBuffer.data.length = 0;
                    _activeElementArrayBuffer.data.writeBytes(data, dataPtr, size);
                }
            }
        }
    }

    /* @private */
    private var debugCubeStream:VertexStream;

    [Internal]
    public function glDebugCube():void {
        if (!_cubeVertexBuffer) {
            _cubeVertexBuffer = context.createVertexBuffer(36, 12);
            _cubeVertexBuffer.uploadFromVector(_cubeVertexData, 0, 36);
        }

        if (!debugCubeStream) {
            debugCubeStream = new VertexStream();
            debugCubeStream.vertexBuffer = _cubeVertexBuffer;
            debugCubeStream.vertexFlags = VertexBufferBuilder.HAS_NORMAL;
            debugCubeStream.polygonOffset = isGLState(ENABLE_POLYGON_OFFSET);
            setupIndexBuffer(debugCubeStream, GL_TRIANGLES, 36);
        }

        var cl:CommandList = _reusableCommandList;
        cl.executeOnCompile = true;
        cl.commands.length = 0;
        cl.activeState = null;

        if (cl.activeState) {
            cl.commands.push(cl.activeState);
            cl.activeState = null;
        }

        cl.commands.push(debugCubeStream);

        //if (log) log.send("========== DEBUG CUBE >>")
        executeCommandList(cl);
        //if (log) log.send("========== DEBUG CUBE <<")
    }

    [Internal]
    public function glEndVertexData(count:uint, mode:uint, data:ByteArray, dataPtr:uint, dataHash:uint, flags:uint):void {
        // FIXME: build an actual VertexBuffer3D
        //var buffer:DataBuffer = acquireBufferFromPool(numElements, data32PerVertext, target)
        CONFIG::debug {
            if (log) log.send("glEnd()");
        }

        // FIXME (egeorgie): refactor into the VertexBufferbuilder
        const data32PerVertex:int = 12; // x, y, z,  r, g, b, a,  nx, ny, nz, tx, ty

        // Number of Vertexes
        if (count == 0) {
            CONFIG::debug {
                if (log) log.send("0 vertices, no-op");
            }
            return;
        }

        var b:VertexBuffer3D;
        if (this._activeCommandList) {
            b = this.context.createVertexBuffer(count, data32PerVertex);
            b.uploadFromByteArray(data, dataPtr, 0, count);
        }
        else {
            b = this._immediateVertexBuffers.acquire(dataHash, count, data, dataPtr);
            if (!b) {
                b = this._immediateVertexBuffers.allocateOrReuse(dataHash, count, data, dataPtr, this.context);
            }
        }

        var cl:CommandList = this._activeCommandList;

        // If we don't have a list, create a temporary one and execute it on glEndList()
        if (!cl) {
            cl = this._reusableCommandList;
            cl.executeOnCompile = true;
            cl.commands.length = 0;
            cl.activeState = null;
        }

        var stream:VertexStream = new VertexStream(); // FIXME: Pooled VertexStream ?
        stream.vertexBuffer = b;
        //stream.indexBuffer = indexBuffer;
        stream.vertexFlags = flags;
        stream.polygonOffset = this.isGLState(ENABLE_POLYGON_OFFSET);

        this.setupIndexBuffer(stream, mode, count);

        // Remember whether we need to generate texture coordiantes on the fly,
        // we'll use that value later on to pick the right shader when we render the list

        if (this._enableTexGenS) {
            if (this._texGenParamS == GL_SPHERE_MAP)
                stream.vertexFlags |= VertexBufferBuilder.TEX_GEN_S_SPHERE;
            else if (log) log.send("[Warning] Unsupported glTexGen mode for GL_S: 0x" + _texGenParamS.toString(16));
        }

        if (this._enableTexGenT) {
            if (this._texGenParamT == GL_SPHERE_MAP)
                stream.vertexFlags |= VertexBufferBuilder.TEX_GEN_T_SPHERE;
            else if (log) log.send("[Warning] Unsupported glTexGen mode for GL_S: 0x" + _texGenParamT.toString(16));
        }

        // Make sure that if we have any active state changes, we push them in front of the stream commands
        if (cl.activeState) {
            cl.commands.push(cl.activeState);
            cl.activeState = null;
        }

        cl.commands.push(stream);

        if (!this._activeCommandList) {
            CONFIG::debug {
                if (log) log.send("Rendering Immediate Vertex Stream ");
            }
            this.executeCommandList(cl);
        }
    }

    [Inline]
    final private function setGLState(bit:uint):void {
        this._glStateFlags |= (1 << bit);
    }

    [Inline]
    final private function clearGLState(bit:uint):void {
        this._glStateFlags &= ~(1 << bit);
    }

    [Inline]
    final private function isGLState(bit:uint):Boolean {
        return 0 != (this._glStateFlags & (1 << bit));
    }

    [Deprecated]
    final private function getFixedFunctionPipelineKey(flags:uint):String {
        // glStateFlags
        // textureSamplers's params
        // textureSamplers's mipLevels

        var key:String = flags.toString() + this._glStateFlags.toString();
        var instance:TextureInstance;
        var textureParams:TextureParams;
//            const zero:String = '0';
//            const one:String = '1';
        const ti:String = 'ti';
        const sep:String = ',';
//            const noop:String = '0,0,0,';

        if (0 != (flags & VertexBufferBuilder.HAS_TEXTURE2D)) {
            for (var i:int = 0; i < 8; ++i) {
                key += ti;
                key += i;
                key += sep;
                instance = this._textureSamplers[i];
                if (instance) {
                    key += instance.key;
//                         textureParams = instance.params
//                         if (!textureParams) {
//                            key += noop;
//                         } else {
//                            key += textureParams.GL_TEXTURE_WRAP_S;
//                            key += sep;
//                            key += textureParams.GL_TEXTURE_WRAP_T;
//                            key += sep;
//                            key += textureParams.GL_TEXTURE_MIN_FILTER;
//                            key += sep;
//                         }
//                         key += (instance.mipLevels > 1 ? one : zero)
                }
                // key = key.concat("ti", i,",")
                // var ti:TextureInstance = textureSamplers[i]

                // if (ti) {
//                        var textureParams:TextureParams = ti.params
                // key = key.concat((textureParams ? textureParams.GL_TEXTURE_WRAP_S : 0), ",",
                //                (textureParams ? textureParams.GL_TEXTURE_WRAP_T : 0), ",",
                //                (textureParams ? textureParams.GL_TEXTURE_MIN_FILTER : 0), ",",
                //                (ti.mipLevels > 1 ? 1 : 0))
                //}
            }

        }
        return key;
    }

    [Deprecated]
    final private function ensureProgramUpToDate(stream:VertexStream):void {
        var flags:uint = stream.vertexFlags;
        CONFIG::debug {
            this.send("stream.vertexFlags is: " + flags);
        }
        var key:String = this.getFixedFunctionPipelineKey(flags);
        CONFIG::debug {
            if (log) log.send("program key is:" + key);
        }

        if (!stream.program || stream.program.key != key)
            stream.program = this.getFixedFunctionPipelineProgram(key, flags);
    }

    [Deprecated]
    final private function getFixedFunctionPipelineProgram(key:String, flags:uint):FixedFunctionProgramInstance {
        var p:FixedFunctionProgramInstance = this._fixedFunctionPrograms[key];

        if (!p) {
            p = new FixedFunctionProgramInstance();
            p.key = key;
            this._fixedFunctionPrograms[key] = p;

            p.program = this.context.createProgram();
            p.hasTexture = this._contextEnableTextures[_activeTextureUnit] &&
                    ((0 != (flags & VertexBufferBuilder.HAS_TEXTURE2D)) ||
                    (0 != (flags & VertexBufferBuilder.TEX_GEN_S_SPHERE) && 0 != (flags & VertexBufferBuilder.TEX_GEN_T_SPHERE)));

            var textureParams:TextureParams = null;
            var ti:TextureInstance;
            if (p.hasTexture) {
                // FIXME (egeorgie): Assume sampler 0
                /* ti = textureSamplers[0] */
                ti = this._textureSamplers[this._activeTextureUnit];
                if (ti)
                    textureParams = ti.params;
            }

            // For all Vertex shaders:
            //
            // va0 - position
            // va1 - color
            // va2 - normal
            // va3 - texture coords
            //
            // vc0,1,2,3 - modelViewProjection
            // vc4,5,6,7 - modelView
            // vc8,9,10,11 - inverse modelView
            // vc12, 13, 14, 15 - texture matrix
            // vc16 - (0, 0.5, 1.0, 2.0)
            // vc17 - current color state (to be used when vertex color is not specified)
            // vc18 - clipPlane0
            // vc19 - clipPlane1
            // vc20 - clipPlane2
            // vc21 - clipPlane3
            // vc22 - clipPlane4
            // vc23 - clipPlane5
            //
            // v6, v7 - reserved for clipping

            // For all Fragment shaders
            // v4 - reserved for specular color
            // v5 - reserved for incoming color (either per-vertex color or the current color state)
            // v6 - dot(clipPlane0, pos), dot(clipPlane1, pos), dot(clipPlane2, pos), dot(clipPlane3, pos)
            // v7 - dot(clipPlane4, pos), dot(clipPlane5, pos)
            //

            const _vertexShader_Color_Flags:uint = 0;//VertexBufferBuilder.HAS_COLOR
            const _vertexShader_Color:String = [
                "m44 op, va0, vc0",     // multiply vertex by modelViewProjection
            ].join("\n");

            const _debugShader_Color:String = [
                "m44 op, va0, vc0",     // multiply vertex by modelViewProjection
                "mov v0, va1",          // copy the vertex color to be interpolated per fragment
                "mov v0, vc16", // solid blue for debugging
            ].join("\n");

            const _fragmentShader_Color:String = [
                "mov ft0, v5",
                "add ft0.xyz, ft0.xyz, v4.xyz",                 // add specular color
                "mov oc, ft0",           // output the interpolated color
            ].join("\n");


            const _vertexShader_Texture_Flags:uint = VertexBufferBuilder.HAS_TEXTURE2D;
            const _vertexShader_Texture:String = [
                "m44 op, va0, vc0",     // multiply vertex by modelViewProjection
                "m44 v1, va3, vc12",    // multiply texture coords by texture matrix
            ].join("\n");

            const _fragmentShader_Texture:String = [
                "tex ft0, v1, fs0 <2d, wrapMode, minFilter> ",     // sample the texture
                "mul ft0, ft0, v5",                             // modulate with the interpolated color (hardcoding GL_TEXTURE_ENV_MODE to GL_MODULATE)
                "add ft0.xyz, ft0.xyz, v4.xyz",                 // add specular color
                "mov oc, ft0",                                  // output interpolated color.
            ].join("\n");

//                for(i=0 i<total i++)
//                {
//                    myEyeVertex = MatrixTimesVector(ModelviewMatrix, myVertex[i])
//                    myEyeVertex = Normalize(myEyeVertex)
//                    myEyeNormal = VectorTimesMatrix(myNormal[i], InverseModelviewMatrix)
//                    reflectionVector = myEyeVertex - myEyeNormal * 2.0 * dot3D(myEyeVertex, myEyeNormal)
//                    reflectionVector.z += 1.0
//                    m = 1.0 / (2.0 * sqrt(dot3D(reflectionVector, reflectionVector)))
//                    //I am emphasizing that we write to s and t. Used to sample a 2D texture.
//                    myTexCoord[i].s = reflectionVector.x * m + 0.5
//                    myTexCoord[i].t = reflectionVector.y * m + 0.5
//                }


            // For all Vertex shaders:
            //
            // va0 - position
            // va1 - color
            // va2 - normal
            // va3 - texture coords
            //
            // vc0,1,2,3 - modelViewProjection
            // vc4,5,6,7 - modelView
            // vc8,9,10,11 - inverse modelView
            // vc12, 13, 14, 15 - texture matrix
            // vc16 - (0, 0.5, 1.0, 2.0)
            //

            const _vertexShader_GenTexSphereST_Flags:uint = VertexBufferBuilder.HAS_NORMAL;
            const _vertexShader_GenTexSphereST:String = [
                "m44 op, va0, vc0",     // multiply vertex by modelViewProjection

                "m44 vt0, va0, vc4",        // eyeVertex = vt0 = pos * modelView
                "nrm vt0.xyz, vt0",         // normalize vt0
                "m44 vt1, va2, vc8",        // eyeNormal = vt1 = normal * inverse modelView
                "nrm vt1.xyz, vt1",

                // vt2 = vt0 - vt1 * 2 * dot(vt0, vt1):
                "dp3 vt4.x, vt0, vt1",          // vt4.x = dot(vt0, vt1)
                "mul vt4.x, vt4.x, vc16.w",     // vt4.x *= 2.0
                "mul vt4, vt1, vt4.x",   // vt4 = vt1 * 2.0 * dot (vt0, vt1)
                "sub vt2, vt0, vt4",    //
                "add vt2.z, vt2.z, vc16.z", // vt2.z += 1.0
                // vt2 is the reflectionVector now

                // m = vt4.x = 1 / (2.0 * sqrt(dot3D(reflectionVector, reflectionVector))
                "dp3 vt4.x, vt2, vt2",
                "sqt vt4.x, vt4.x",
                "mul vt4.x, vt4.x, vc16.w",
                "rcp vt4.x, vt4.x",
                // vt4.x is m now

                // myTexCoord[i].s = reflectionVector.x * m + 0.5
                // myTexCoord[i].t = reflectionVector.y * m + 0.5
                "mul vt3.x, vt2.x, vt4.x",
                "add vt3.x, vt3.x, vc16.y",  // += 0.5
                "mul vt3.y, vt2.y, vt4.x",
                "add vt3.y, vt3.y, vc16.y",  // += 0.5

                // zero-out the rest z & w
                "mov vt3.z, vc16.x",
                "mov vt3.w, vc16.x",

                // copy the texture coordiantes to be interpolated per fragment
                "mov v1, vt3",
                // "mov v1, va2",          // copy the vertex color to be interpolated per fragment
            ].join("\n");

            const _fragmentShader_GenTexSphereST:String = [
                "tex ft0, v1, fs0 <2d, wrapMode, minFilter> ",     // sample the texture
                "mul ft0, ft0, v5",                             // modulate with the interpolated color (hardcoding GL_TEXTURE_ENV_MODE to GL_MODULATE)
                "add ft0.xyz, ft0.xyz, v4.xyz",                 // add specular color
                "mov oc, ft0",
            ].join("\n");

            var vertexShader:String;
            var fragmentShader:String;

            if (p.hasTexture) {
                if (0 != (flags & VertexBufferBuilder.TEX_GEN_S_SPHERE) &&
                        0 != (flags & VertexBufferBuilder.TEX_GEN_T_SPHERE)) {
                    CONFIG::debug {
                        if (log) log.send("using reflection shaders...");
                    }
                    vertexShader = _vertexShader_GenTexSphereST;
                    p.vertexStreamUsageFlags = _vertexShader_GenTexSphereST_Flags;
                    fragmentShader = _fragmentShader_GenTexSphereST;
                }
                else if (0 != (flags & VertexBufferBuilder.HAS_TEXTURE2D)) {
                    CONFIG::debug {
                        if (log) log.send("using texture shaders...");
                    }
                    vertexShader = _vertexShader_Texture;
                    p.vertexStreamUsageFlags = _vertexShader_Texture_Flags;

                    CONFIG::debug {
                        if (textureParams.GL_TEXTURE_WRAP_S != textureParams.GL_TEXTURE_WRAP_T) {
                            if (log) log.send("[Warning] Unsupported different texture addressing modes for S and T: 0x" +
                                    textureParams.GL_TEXTURE_WRAP_S.toString(16) + ", 0x" +
                                    textureParams.GL_TEXTURE_WRAP_T.toString(16));
                        }
                    }

                    CONFIG::debug {
                        if (textureParams.GL_TEXTURE_WRAP_S != GL_REPEAT && textureParams.GL_TEXTURE_WRAP_S != GL_CLAMP) {
                            if (log) log.send("[Warning] Unsupported texture wrap mode: 0x" +
                                    textureParams.GL_TEXTURE_WRAP_S.toString(16));
                        }
                    }

                    var wrapModeS:String = (textureParams.GL_TEXTURE_WRAP_S == GL_REPEAT) ? "repeat" : "clamp";
                    fragmentShader = _fragmentShader_Texture.replace("wrapMode", wrapModeS);

                    CONFIG::debug {
                        if (log) log.send("mipmapping levels " + ti.mipLevels);
                    }

                    if (ti.mipLevels > 1) {
                        /* fragmentShader = fragmentShader.replace("minFilter", "linear, miplinear, -2.0") */
                        fragmentShader = fragmentShader.replace("minFilter", "linear, miplinear");
                    }
                    else if (textureParams.GL_TEXTURE_MIN_FILTER == GL_NEAREST) {
                        fragmentShader = fragmentShader.replace("minFilter", "nearest, nomip");
                    }
                    else {
                        fragmentShader = fragmentShader.replace("minFilter", "linear, nomip");
                    }
                }
            }
            else {
                CONFIG::debug {
                    if (log) log.send("using color shaders...");
                }
                vertexShader = _vertexShader_Color;
                p.vertexStreamUsageFlags = _vertexShader_Color_Flags;
                fragmentShader = _fragmentShader_Color;
            }

            // CALCULATE VERTEX COLOR
            var useVertexColor:Boolean = (0 != (flags & VertexBufferBuilder.HAS_COLOR));
            if (useVertexColor)
                p.vertexStreamUsageFlags |= VertexBufferBuilder.HAS_COLOR;

            if (_contextEnableLighting) {

                // va0 - position
                // va1 - color
                // va2 - normal
                // va3 - texture coords
                //
                // vc0,1,2,3 - modelViewProjection
                // vc4,5,6,7 - modelView
                // vc8,9,10,11 - inverse modelView
                // vc12, 13, 14, 15 - texture matrix
                // vc16 - (0, 0.5, 1.0, 2.0)
                // vc17 - current color state (to be used when vertex color is not specified)
                // vc18-vc23 - clipPlanes
                // vc24 - viewpoint (origin of eyespace)
                // vc25 - mat_ambient
                // vc26 - mat_diffuse
                // vc27 - mat_specular
                // vc28 - mat_shininess (in the form [shininess, 0, 0, 0])
                // vc29 - mat_emission
                // vc30 - global ambient lighting
                // vc31 - light 0 position (in eye-space)
                // vc32 - light 0 ambient
                // vc33 - light 0 diffuse
                // vc34 - light 0 specular
                // vc35-38 - light 1
                // vc39-42 - light 2
                // vc43-46 - light 3
                // vc47-50 - light 4
                // vc51-54 - light 5
                // vc55-58 - light 6
                // vc59-62 - light 7
                //
                // v6, v7 - reserved for clipping

                // vertex color =
                //    emissionmaterial +
                //    ambientlight model * ambientmaterial +
                //    [ambientlight *ambientmaterial +
                //     (max { L · n , 0} ) * diffuselight * diffusematerial +
                //     (max { s · n , 0} )shininess * specularlight * specularmaterial ] per light.
                // vertex alpha = diffuse material alpha

                p.vertexStreamUsageFlags |= VertexBufferBuilder.HAS_NORMAL;

                // matColorReg == ambient and diffuse material color to use
                var matAmbReg:String = (_contextColorMaterial) ?
                        ((useVertexColor) ? "va1" : "vc17") : "vc25";
                var matDifReg:String = (_contextColorMaterial) ?
                        ((useVertexColor) ? "va1" : "vc17") : "vc26";

                // FIXME (klin): Need to refactor to take into account multiple lights...
                /*var lightingShader:String = [
                 "mov vt0, vc29",                   // start with emission material
                 "add vt0, vt0, " + matAmbReg,      // add ambient material color
                 "add vt0, vt0, " + matDifReg,      // add diffuse material color
                 "mov vt0.w, " + matDifReg + ".w",  // alpha = diffuse material alpha
                 "sat vt0, vt0",                    // clamp to 0 or 1
                 "mov v5, vt0",
                 ].join("\n")*/

                // v5 = vt3 will be used to calculate the final color.
                // v4 = vt7 is the specular color if contextSeparateSpecular == true
                //      otherwise, specular is included in v5.
                var lightingShader:String = [
                    // init v4 to 0
                    "mov v4.xyzw, vc16.xxxx",

                    // calculate some useful constants
                    // vt0 = vertex in eye space
                    // vt1 = normalized normal vector in eye space
                    // vt2 = |V| = normalized vector from origin of eye space to vertex
                    "m44 vt0, va0, vc4",               // vt0 = vertex in eye space
                    "mov vt1, va2",                    // vt1 = normal vector
                    "m33 vt1.xyz, vt1, vc4",           // vt1 = normal vector in eye space
                    "nrm vt1.xyz, vt1",                // vt1 = n = norm(normal vector)
                    "neg vt2, vt0",                    // vt2 = V = origin - vertex in eye space
                    "nrm vt2.xyz, vt2",                // vt2 = norm(V)

                    // general lighting
                    "mov vt3, vc29",                   // start with emission material
                    "mov vt4, vc30",                   // vt4 = global ambient light
                    "mul vt4, vt4, " + matAmbReg,      // global ambientlight model * ambient material
                    "add vt3, vt3, vt4",               // add ambient color from global light

                    // Light specific calculations

                    // Initialize temp for specular
                    "mov vt7, vc16.xxxx",              // vt7 is specular, will end in v4

                    //   ambient color
//                        "mov vt4, vc32",
//                        "mul vt4, vt4, " + matAmbReg,      // ambientlight0 * ambientmaterial
//                        "add vt3, vt3, vt4",               // add ambient color from light0
//
//                        //   diffuse color
//                        "sub vt4, vc31, vt0",              // vt4 = L = light0 pos - vertex pos
//                        "nrm vt4.xyz, vt4",                // vt4 = norm(L)
//                        "mov vt5, vt1",
//                        "dp3 vt5.x, vt4, vt5",             // vt5.x = L · n
//                        "max vt5.x, vt5.x, vc16.x",        // vt5.x = max { L · n , 0}
//                        "neg vt6.x, vt5.x",                // check if L · n is <= 0
//                        "slt vt6.x, vt6.x, vc16.x",
//                        "mul vt5.xyz, vt5.xxx, vc33.xyz",  // vt5 = vt5.x * diffuselight0
//                        "mul vt5, vt5, " + matDifReg,      // vt0 = vt0 * diffusematerial
//                        "add vt3, vt3, vt5",               // add diffuse color from light0
//
//                        //   specular color
//                        "add vt5, vt4, vt2",               // vt5 = s = L + V
//                        "nrm vt5.xyz, vt5",                // vt5 = norm(s)
//                        "dp3 vt5.x, vt5, vt1",             // vt5.x = s · n
//                        "max vt5.x, vt5.x, vc16.x",        // vt5.x = max { s · n , 0}
//                        "pow vt5.x, vt5.x, vc28.x",        // vt5.x = max { s · n , 0}^shininess
//                        "max vt5.x, vt5.x, vc16.x",        // make sure vt5 is not negative.
//                        "mul vt5.xyz, vt5.xxx, vc34.xyz",  // vt5 = vt5.x * specularlight0
//                        "mul vt5, vt5, vc27",              // vt5 = vt5 * specularmaterial
//                        "mul vt5, vt5.xyz, vt6.xxx",       // specular = 0 if L · n is <= 0.

//                        "sat vt5, vt5",
//                        "mov v4, vt5",                     // specular is separate and added later.
//
//                        //"add vt3, vt3, vt5",               // add specular color from light0
//
//                        // alpha determined by diffuse material
//                        "mov vt3.w, " + matDifReg + ".w",  // alpha = diffuse material alpha
//
//                        "sat vt3, vt3",                    // clamp to 0 or 1
//                        "mov v5, vt3",                     // v5 = final color
                ].join("\n");

                CONFIG::debug {
                    if (!_lightsEnabled[0] && !_lightsEnabled[1])
                        if (log) log.send("GL_LIGHTING enabled, but no lights are enabled...");
                }

                // concatenate shader for each light
                for (var i:int = 0; i < 8; i++) {
                    if (!_lightsEnabled[i])
                        continue;

                    var l:Light = _lights[i];
                    var starti:int = 31 + i * 4;
                    var lpos:String = "vc" + starti.toString();
                    var lamb:String = "vc" + (starti + 1).toString();
                    var ldif:String = "vc" + (starti + 2).toString();
                    var lspe:String = "vc" + (starti + 3).toString();

                    var lightVectorAgalInstr:String;
                    if (l.type == Light.LIGHT_TYPE_DIRECTIONAL) {
                        lightVectorAgalInstr = "mov vt4, " + lpos;
                    }
                    else	// Assume point light
                    {
                        lightVectorAgalInstr = "sub vt4, " + lpos + ", vt0";
                    }

                    var lightpiece:String = [
                        //   ambient color
                        "mov vt4, " + lamb,
                        "mul vt4, vt4, " + matAmbReg,      // ambientlight0 * ambientmaterial
                        "add vt3, vt3, vt4",               // add ambient color from light0

                        //   diffuse color
                        lightVectorAgalInstr,    		   // vt4 = L = light0 pos - vertex pos
                        "nrm vt4.xyz, vt4",                // vt4 = norm(L)
                        "mov vt5, vt1",
                        "dp3 vt5.x, vt4, vt5",             // vt5.x = L · n
                        "max vt5.x, vt5.x, vc16.x",        // vt5.x = max { L · n , 0}
                        "neg vt6.x, vt5.x",                // check if L · n is <= 0
                        "slt vt6.x, vt6.x, vc16.x",
                        "mul vt5.xyz, vt5.xxx, " + ldif + ".xyz",  // vt5 = vt5.x * diffuselight0
                        "mul vt5, vt5, " + matDifReg,      // vt0 = vt0 * diffusematerial
                        "add vt3, vt3, vt5",               // add diffuse color from light0

                        //   specular color
                        "add vt5, vt4, vt2",               // vt5 = s = L + V
                        "nrm vt5.xyz, vt5",                // vt5 = norm(s)
                        "dp3 vt5.x, vt5, vt1",             // vt5.x = s · n
                        "max vt5.x, vt5.x, vc16.x",        // vt5.x = max { s · n , 0}
                        "pow vt5.x, vt5.x, vc28.x",        // vt5.x = max { s · n , 0}^shininess
                        "max vt5.x, vt5.x, vc16.x",        // make sure vt5 is not negative.
                        "mul vt5.xyz, vt5.xxx, " + lspe + ".xyz",  // vt5 = vt5.x * specularlight0
                        "mul vt5, vt5, vc27",              // vt5 = vt5 * specularmaterial
                        "mul vt5, vt5.xyz, vt6.xxx",       // specular = 0 if L · n is <= 0.
                        "add vt7, vt7, vt5",               // add specular to output (will be in v4)
                    ].join("\n");

                    lightingShader = lightingShader + "\n" + lightpiece;
                }

                lightingShader = lightingShader + "\n" + [
                            "sat vt7, vt7",
                            "mov v4, vt7",                     // specular is separate and added later.

                            // alpha determined by diffuse material
                            "mov vt3.w, " + matDifReg + ".w",  // alpha = diffuse material alpha

                            "sat vt3, vt3",                    // clamp to 0 or 1
                            "mov v5, vt3",                     // v5 = final color
                        ].join("\n");

                if (useVertexColor)
                    lightingShader = "mov vt0, va1\n" + lightingShader; //HACK
                vertexShader = lightingShader + "\n" + vertexShader;
            }
            else if (useVertexColor) {
                // Color should come from the vertex buffer
                // also init v4 to 0.
                vertexShader = "mov v4.xyzw, vc16.xxxx\n" + "mov v5, va1" + "\n" + vertexShader;
            }
            else {
                // Color should come form the current color
                // also init v4 to 0.
                vertexShader = "mov v4.xyzw, vc16.xxxx\n" + "mov v5, vc17" + "\n" + vertexShader;
            }

            // CLIPPING
            var clippingOn:Boolean = _clipPlaneEnabled[0] || _clipPlaneEnabled[1] || _clipPlaneEnabled[2] ||
                _clipPlaneEnabled[3] || _clipPlaneEnabled[4] || _clipPlaneEnabled[5];
            if (clippingOn) {
                // va0 - position
                // va1 - color
                // va2 - normal
                // va3 - texture coords
                //
                // vc0,1,2,3 - modelViewProjection
                // vc4,5,6,7 - modelView
                // vc8,9,10,11 - inverse modelView
                // vc12, 13, 14, 15 - texture matrix
                // vc16 - (0, 0.5, 1.0, 2.0)
                // vc17 - current color state (to be used when vertex color is not specified)
                // vc18 - clipPlane0
                // vc19 - clipPlane1
                // vc20 - clipPlane2
                // vc21 - clipPlane3
                // vc22 - clipPlane4
                // vc23 - clipPlane5
                //
                // v6, v7 - reserved for clipping

                // For all Fragment shaders
                //
                // v6 - dot(clipPlane0, pos), dot(clipPlane1, pos), dot(clipPlane2, pos), dot(clipPlane3, pos)
                // v7 - dot(clipPlane4, pos), dot(clipPlane5, pos)
                //
                const clipVertex:String = [
                    "m44 vt0, va0, vc4",        // position in eye (modelVeiw) space
                    "dp4 v6.x, vt0, vc18",       // calculate clipPlane0
                    "dp4 v6.y, vt0, vc19",       // calculate clipPlane1
                    "dp4 v6.z, vt0, vc20",       // calculate clipPlane2
                    "dp4 v6.w, vt0, vc21",       // calculate clipPlane3
                    "dp4 v7.x, vt0, vc22",       // calculate clipPlane4
                    "dp4 v7.yzw, vt0, vc23",       // calculate clipPlane5
                ].join("\n");

                const clipFragment:String = [
                    "min ft0.x, v6.x, v6.y",
                    "min ft0.y, v6.z, v6.w",
                    "min ft0.z, v7.x, v7.y",
                    "min ft0.w, ft0.x, ft0.y",
                    "min ft0.w, ft0.w, ft0.z",
                    "kil ft0.w",
                ].join("\n");

                vertexShader = clipVertex + "\n" + vertexShader;
                fragmentShader = clipFragment + "\n" + fragmentShader;
            }

            CONFIG::debug {
                if (log) {
                    log.send("vshader:\n" + vertexShader);
                    log.send("fshader:\n" + fragmentShader);
                }
            }

            // FIXME (egeorgie): cache the agalcode? Using a shared assembler ?.
            var vsAssembler:AGALMiniAssembler = new AGALMiniAssembler;
            vsAssembler.assemble(Context3DProgramType.VERTEX, vertexShader);
            var fsAssembler:AGALMiniAssembler = new AGALMiniAssembler;
            fsAssembler.assemble(Context3DProgramType.FRAGMENT, fragmentShader);
            p.program.upload(vsAssembler.agalcode, fsAssembler.agalcode);
        }

        return p;
    }

    [Internal]
    public function glColor(r:Number, g:Number, b:Number, alpha:Number):void {
        // Change current color if we're not recording a command
        if (!this._activeCommandList) {
            this._contextColor[0] = r;
            this._contextColor[1] = g;
            this._contextColor[2] = b;
            this._contextColor[3] = alpha;
        }
    }

    [Internal]
    public function glNewList(id:uint, mode:uint):void {
        // Allocate and active a new CommandList
        CONFIG::debug {
            if (log) log.send("glNewList : " + id + ", compileAndExecute = " + (mode == GL_COMPILE_AND_EXECUTE).toString());
        }
        this._activeCommandList = new CommandList();
        this._activeCommandList.executeOnCompile = (mode == GL_COMPILE_AND_EXECUTE);
        this._commandLists[id] = this._activeCommandList;
    }

    [Internal]
    public function glEndList():void {
        // Make sure if we have any pending state changes, we push them as a command at the end of the list
        if (this._activeCommandList.activeState) {
            this._activeCommandList.commands.push(this._activeCommandList.activeState);
            this._activeCommandList.activeState = null;
        }

        if (this._activeCommandList.executeOnCompile)
            this.executeCommandList(this._activeCommandList);

        // We're done with this list, it's no longer active
        this._activeCommandList = null;
    }

    [Internal]
    public function glCallList(id:uint):void {
        CONFIG::debug {
            if (log) log.send("glCallList");

            if (this._activeCommandList)
                if (log) log.send("Warning: Calling a command list while building a command list not yet implemented.");

            if (log) log.send("Rendering List " + id);
        }

        this.executeCommandList(this._commandLists[id]);
    }

    [Inline]
    final public function get playerVersionNumber():Vector.<int> {
        if (this._playerVersionNumber[0] == 0) {
            var versionNum:String = Capabilities.version.split(' ')[1];
            var versionNumComponents:Array = versionNum.split(',');
            this._playerVersionNumber[0] = parseInt(versionNumComponents[0]);
            this._playerVersionNumber[1] = parseInt(versionNumComponents[1]);
            this._playerVersionNumber[2] = parseInt(versionNumComponents[2]);
            this._playerVersionNumber[3] = parseInt(versionNumComponents[3]);
        }
        return this._playerVersionNumber;
    }

    /**
     * Auto preferred to a suitable version of AGAL.
     *
     * @param context A Context3D which created.
     * @param logObj A log object API.
     * @return A unsigned integer describes the version number of AGAL.
     */
    protected function preferredAGALVersion(context:Context3D, logObj:Object = null):uint {
        // Auto selected the most suitable AGAL version.
        var matches:Array = /^(\w+)\s+\((\w+)\s*(\w+)?\)$/g.exec(context.driverInfo);
        if (matches && matches.length > 1) {
            this._driverAPI = matches[1];
            var extended:Boolean = matches.length > 3 && matches[3] == "Extended";
            var constrained:Boolean = matches.length > 3 && matches[3] == "Constrained";

            if (matches[2] == "Baseline") {
                if (constrained)
                    this._profileIndex = 1; // Baseline Constrained
                else if (!extended)
                    this._profileIndex = 2; // Baseline
                else
                    this._profileIndex = 3; // Baseline Extended
            }
            else if (matches[2] == "Standard") {
                if (constrained)
                    this._profileIndex = 4; // Standard Constrained
                else if (!extended)
                    this._profileIndex = 5; // Standard
                else
                    this._profileIndex = 6; // Standard Extended
            }

            if (logObj) {
                logObj.send("Driver API: " + this._driverAPI + "\n");
                logObj.send("Driver Base Profile: " + matches[2] + "\n");
                logObj.send("Driver Extended: " + (extended ? "true" : "false"));
                logObj.send("Driver Constrained: " + (constrained ? "true" : "false"));
            }

            if (this._profileIndex >= 6) {
                /* return this.playerVersionNumber[0] >= 26 ? 4 : 3; */
                return 3;
            }
            else if (this._profileIndex >= 4) {
                return 2;
            }
        }
        // or any doesn't had a HW acc, make basic agal working.
        return 1;
    }

    protected function initGLCapabilities():void {
        const limits:Dictionary = this._glLimits;
        const hw_disabled:Boolean = this.context.driverInfo.indexOf("Hw_disabled") != -1;
        void(hw_disabled);
        var extensions:String = "";

        limits[GL_MAX_SAMPLES] = 16;
        limits[GL_MAX_VERTEX_ATTRIBS] = 8;
        limits[GL_MAX_VARYING_VECTORS] = 8;
        limits[GL_MAX_VERTEX_UNIFORM_VECTORS] = 128;
        limits[GL_MAX_FRAGMENT_UNIFORM_VECTORS] = 28;
        limits[GL_MAX_TEXTURE_UNITS] = 8;
        limits[GL_MAX_TEXTURE_SIZE] = 1024 * 1024;
        limits[GL_MAX_COLOR_ATTACHMENTS] = 1;
        limits[GL_MAX_DRAW_BUFFERS] = 8;

        extensions += "GL_ARB_compatibility ";
        extensions += "GL_ARB_multitexture ";
        extensions += "GL_ARB_multisample ";
        extensions += "GL_EXT_compiled_vertex_array ";
        extensions += "GL_EXT_texture_env_combine ";
        extensions += "GL_EXT_framebuffer_object ";
        extensions += "GL_EXT_framebuffer_blit ";
        extensions += "GL_ARB_draw_buffers ";
        extensions += "GL_ARB_seamless_cube_map ";
        extensions += "ADOBE_AGAL_1 ";

        extensions += "GL_ARB_texture_buffer_object ";

        if (playerVersionNumber[0] >= 13) {
            extensions += "GL_EXT_framebuffer_multisample ";
            extensions += "GL_ARB_texture_multisample ";
            limits[GL_MAX_COLOR_TEXTURE_SAMPLES] = limits[GL_MAX_SAMPLES];
            limits[GL_MAX_DEPTH_TEXTURE_SAMPLES] = limits[GL_MAX_SAMPLES];
        }

        if (this._profileIndex > 0) {
            limits[GL_MAX_TEXTURE_SIZE] = 2048 * 2048;
        }

        if (this._profileIndex >= 3) {
            limits[GL_MAX_TEXTURE_SIZE] = 4096 * 4096;
        }

        if (this._profileIndex >= 4 && _agalVersion >= 2) {
            limits[GL_MAX_VERTEX_UNIFORM_VECTORS] = 250;
            limits[GL_MAX_FRAGMENT_UNIFORM_VECTORS] = 64;

            extensions += "ADOBE_AGAL_2 ";

            extensions += "GL_OES_texture_float ";
            extensions += "GL_OES_texture_half_float ";
            extensions += "GL_ARB_texture_float ";
            extensions += "GL_ARB_half_float_pixel ";
            extensions += "GL_OES_depth_texture ";
            extensions += "GL_ARB_depth_buffer_float ";
            extensions += "GL_ARB_texture_non_power_of_two ";
            extensions += "GL_EXT_texture_filter_anisotropic ";
            extensions += "GL_OES_element_index_uint ";
        }

        if (this._profileIndex >= 5) {
            limits[GL_MAX_COLOR_ATTACHMENTS] = 4;
            limits[GL_MAX_VARYING_VECTORS] = 10;
            limits[GL_MAX_TEXTURE_UNITS] = 16;
        }

        if (this._profileIndex >= 6 && _agalVersion >= 3) {
            limits[GL_MAX_VERTEX_ATTRIBS] = 16;
            limits[GL_MAX_FRAGMENT_UNIFORM_VECTORS] = 200;

            extensions += "ADOBE_AGAL_3 ";
            extensions += "GL_ARB_draw_instanced ";
            extensions += "GL_ARB_instanced_arrays ";

            if (playerVersionNumber[0] >= 26)
                extensions += "ADOBE_AGAL_4 ";
        }

        limits[GL_MAX_CUBE_MAP_TEXTURE_SIZE] = 1024 * 1024;
        limits[GL_MAX_VERTEX_UNIFORM_COMPONENTS] = limits[GL_MAX_VERTEX_UNIFORM_VECTORS] * 4;
        limits[GL_MAX_FRAGMENT_UNIFORM_COMPONENTS] = limits[GL_MAX_FRAGMENT_UNIFORM_VECTORS] * 4;
        limits[GL_MAX_RENDERBUFFER_SIZE] = limits[GL_MAX_TEXTURE_SIZE];

        this._glExtensions = extensions;
    }

    public function GLAPI(context:Context3D, stage:Stage, log:Object, log2:Object, useAgalVersion:uint):void {
        // For the debug console
        this._stage = stage;

        this.log = log;
        this.log2 = log2;

        var logObj:Object = this.log || this.log2;

        // passing the agal version by external.
        this._agalVersion = preferredAGALVersion(context, logObj); // preferredAGALVersion must be call first for detecting DriverInfo.
        if (useAgalVersion)
            this._agalVersion = useAgalVersion;

        CONFIG::debug {
            if (logObj) logObj.send("Selected AGAL version: " + _agalVersion + "\n");
        }

        this.context = context;

        this.initGLCapabilities();

        this._agalAssembler = new AGALMiniAssembler();

        const indices:Array = [
            0, 1, 2,
            3, 2, 1,
            4, 0, 6,
            6, 0, 2,
            5, 1, 4,
            4, 1, 0,
            7, 3, 1,
            7, 1, 5,
            5, 4, 7,
            7, 4, 6,
            7, 2, 3,
            7, 6, 2];

        const vertices:Array = [
            [1.0, 1.0, 1.0],
            [-1.0, 1.0, 1.0],
            [1.0, -1.0, 1.0],
            [-1.0, -1.0, 1.0],
            [1.0, 1.0, -1.0],
            [-1.0, 1.0, -1.0],
            [1.0, -1.0, -1.0],
            [-1.0, -1.0, -1.0]];

        this._cubeVertexData = new Vector.<Number>();
        var si:int = 36;
        var i:int;
        for (i = 0; i < si; i += 3) {
            const v1:Array = vertices[indices[i]];
            const v2:Array = vertices[indices[i + 1]];
            const v3:Array = vertices[indices[i + 2]];
            this._cubeVertexData.push(v1[0], v1[1], v1[2], 1, 1, 1, 1, 0, 0, 0, 0, 0);
            this._cubeVertexData.push(v2[0], v2[1], v2[2], 1, 1, 1, 1, 0, 0, 0, 0, 0);
            this._cubeVertexData.push(v3[0], v3[1], v3[2], 1, 1, 1, 1, 0, 0, 0, 0, 0);
        }

        this.NULL_TEXTURE = this.context.createTexture(1, 1, Context3DTextureFormat.BGRA, false);
    }

    [Internal]
    public function glClear(mask:uint):void {
        CONFIG::debug {
            if (log) log.send("glClear called with " + mask);
        }

        this._contextClearMask = 0;
        if (Boolean(mask & GL_COLOR_BUFFER_BIT)) this._contextClearMask |= Context3DClearMask.COLOR;
        if (Boolean(mask & GL_STENCIL_BUFFER_BIT)) this._contextClearMask |= Context3DClearMask.STENCIL;
        if (Boolean(mask & GL_DEPTH_BUFFER_BIT)) this._contextClearMask |= Context3DClearMask.DEPTH;

        this.context.clear(this._contextClearR, this._contextClearG, this._contextClearB, this._contextClearA,
                this._contextClearDepth, this._contextClearStencil, this._contextClearMask);

        // Make sure the vertex buffer pool knows it's next frame already to enable recycling
        if (this._immediateVertexBuffers)
            this._immediateVertexBuffers.nextFrame();
    }

    [Internal]
    public function glClearColor(red:Number, green:Number, blue:Number, alpha:Number):void {
        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glClearColor " + red + " " + green + " " + blue + " " + alpha + "\n");
        }

        this._contextClearR = red;
        this._contextClearG = green;
        this._contextClearB = blue;
        this._contextClearA = alpha;
    }

    [Internal]
    public function glActiveTexture(index:uint):void {
        var unitIndex:uint = index - GL_TEXTURE0;
        if (unitIndex <= 31) {
            this._activeTextureUnit = unitIndex;
            CONFIG::debug {
                if (log) log.send("[IMPLEMENTED] glActiveTexture " + this._activeTextureUnit + "\n");
            }
        }
        else {
            if (log) log.send("[ERROR] Invalid texture unit requested " + uint);
        }
    }

    [Internal]
    public function glBindTexture(type:uint, texture:uint):void {
        this._textureSamplerIDs[this._activeTextureUnit] = texture;

        if (texture == 0) { // Bind texture to null.
            if (!this._textures[0]) {
                this._textures[0] = new TextureInstance();
                this._textures[0].texID = 0;
                this._textures[0].texture = this.NULL_TEXTURE;
            }

            // FIXME (egeorgie): just set the sampler to null and clear the active texture params?
            CONFIG::debug {
                if (log) log.send("Trying bind the non-existent texture 0!");
            }
            return;
        }

        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glBindTexture " + type + " " + texture + ", tu: " + _activeTextureUnit + "\n");
            if (log2) log2.send("[IMPLEMENTED] glBindTexture Sampler " + texture + " resolves into " + _textures[texture] + "\n");
        }

        if (this._activeCommandList) {
            CONFIG::debug {
                if (log) log.send("Recording texture " + texture + " for the active list.");
            }

            var activeState:ContextState = this._activeCommandList.ensureActiveState();
            activeState.textureSamplers[this._activeTextureUnit] = texture;
        }

        this._activeTexture = _textures[texture];
        this._activeTexture.boundType = type;
        this._textureSamplers[this._activeTextureUnit] = this._activeTexture;

        CONFIG::debug {
            if (type != GL_TEXTURE_2D && type != GL_TEXTURE_CUBE_MAP) {
                if (log) log.send("[NOTE] Unsupported texture type " + type + " for glBindTexture");
            }
        }
    }

    final private function glCullModeToContext3DTriangleFace(mode:uint, frontFaceClockWise:Boolean):String {
        switch (mode) {
            case GL_FRONT: //log.send("culling=GL_FRONT")
                return frontFaceClockWise ? Context3DTriangleFace.FRONT : Context3DTriangleFace.BACK;
            case GL_BACK: //log.send("culling=GL_BACK")
                return frontFaceClockWise ? Context3DTriangleFace.BACK : Context3DTriangleFace.FRONT;
            case GL_FRONT_AND_BACK: //log.send("culling=GL_FRONT_AND_BACK")
                return Context3DTriangleFace.FRONT_AND_BACK;
            default:
                if (log) log.send("[WARNING] Unsupported glCullFace mode: 0x" + mode.toString(16));
                return Context3DTriangleFace.NONE;
        }
    }

    [Internal]
    public function glCullFace(mode:uint):void {
        CONFIG::debug {
            if (log) log.send("glCullFace");
        }

        if (this._activeCommandList)
            if (log) log.send("[Warning] Recording glCullMode as part of command list not yet implememnted");

        this._glCullMode = mode;

        // culling affects the context3D stencil
        this.commitStencilState();

        if (this._contextEnableCulling)
            this.context.setCulling(this.disableCulling ? Context3DTriangleFace.NONE :
                    glCullModeToContext3DTriangleFace(this._glCullMode, this._frontFaceClockWise));
    }

    [Internal]
    public function glFrontFace(mode:uint):void {
        CONFIG::debug {
            if (log) log.send("glFrontFace");
        }

        if (this._activeCommandList)
            if (log) log.send("[Warning] Recording glFrontFace as part of command list not yet implememnted");

        this._frontFaceClockWise = (mode == GL_CW);

        // culling affects the context3D stencil
        this.commitStencilState();

        if (this._contextEnableCulling)
            this.context.setCulling(this.disableCulling ? Context3DTriangleFace.NONE :
                    glCullModeToContext3DTriangleFace(this._glCullMode, this._frontFaceClockWise));
    }

    [Internal]
    public function glEnable(cap:uint):void {
        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glEnable 0x" + cap.toString(16) + "\n");
        }

        switch (cap) {
            case GL_DEPTH_TEST:
                this._contextEnableDepth = true;
                this.context.setDepthTest(this._contextDepthMask, this._contextDepthFunction);
                break;
            case GL_CULL_FACE:
                if (!this._contextEnableCulling) {
                    this._contextEnableCulling = true;
                    this.context.setCulling(this.disableCulling ? Context3DTriangleFace.NONE :
                            glCullModeToContext3DTriangleFace(this._glCullMode, this._frontFaceClockWise));

                    // Stencil depends on culling
                    this.commitStencilState();
                }
                break;
            case GL_STENCIL_TEST:
                if (!this._contextEnableStencil) {
                    this._contextEnableStencil = true;
                    this.commitStencilState();
                }
                break;
            case GL_SCISSOR_TEST:
                if (!this._contextEnableScissor) {
                    this._contextEnableScissor = true;
                    if (!this._scissorRect)
                        this._scissorRect = new Rectangle(0, 0, this._contextWidth, this._contextHeight);

                    this.context.setScissorRectangle(this._scissorRect);
                }
                break;
            case GL_ALPHA_TEST:
                this._contextEnableAlphaTest = true;
                break;
            case GL_BLEND:
                this._contextEnableBlending = true;
                if (!this.disableBlending)
                    this.context.setBlendFactors(this._contextSrcBlendFunc, this._contextDstBlendFunc);
                break;

            case GL_TEXTURE_GEN_S:
                this._enableTexGenS = true;
                break;

            case GL_TEXTURE_GEN_T:
                this._enableTexGenT = true;
                break;

            case GL_CLIP_PLANE0:
            case GL_CLIP_PLANE1:
            case GL_CLIP_PLANE2:
            case GL_CLIP_PLANE3:
            case GL_CLIP_PLANE4:
            case GL_CLIP_PLANE5:
                var clipPlaneIndex:int = cap - GL_CLIP_PLANE0;
                this._clipPlaneEnabled[clipPlaneIndex] = true;
                this.setGLState(ENABLE_LIGHT_OFFSET + clipPlaneIndex);
                break;

            case GL_TEXTURE_2D:
                /* contextEnableTextures = true */
                this._contextEnableTextures[this._activeTextureUnit] = true;
                this.setGLState(ENABLE_TEXTURE_OFFSET);
                break;

            case GL_LIGHTING:
                this._contextEnableLighting = true;
                this.setGLState(ENABLE_LIGHTING_OFFSET);
                break;

            case GL_COLOR_MATERIAL:
                this._contextColorMaterial = true; // default is GL_FRONT_AND_BACK and GL_AMBIENT_AND_DIFFUSE
                this.setGLState(ENABLE_COLOR_MATERIAL_OFFSET);
                break;

            case GL_LIGHT0:
            case GL_LIGHT1:
            case GL_LIGHT2:
            case GL_LIGHT3:
            case GL_LIGHT4:
            case GL_LIGHT5:
            case GL_LIGHT6:
            case GL_LIGHT7:
                var lightIndex:int = cap - GL_LIGHT0;
                if (this._lights[lightIndex] == null) {
                    this._lights[lightIndex] = new Light(true, lightIndex == 0);
                }
                this._lightsEnabled[lightIndex] = true;
                this.setGLState(ENABLE_LIGHT_OFFSET + lightIndex);
                break;

            case GL_POLYGON_OFFSET_FILL:
                this._contextEnablePolygonOffset = true;
                this.setGLState(ENABLE_POLYGON_OFFSET);
                break;

            default:
                if (log) log.send("[ERROR] Unsupported cap for glEnable: 0x" + cap.toString(16));
        }
    }

    [Internal]
    public function glDisable(cap:uint):void {
        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glDisable 0x" + cap.toString(16) + "\n");
        }

        switch (cap) {
            case GL_DEPTH_TEST:
                this.context.setDepthTest((_contextEnableDepth = false), Context3DCompareMode.ALWAYS);
                break;
            case GL_CULL_FACE:
                if (this._contextEnableCulling) {
                    this._contextEnableCulling = false;
                    this.context.setCulling(Context3DTriangleFace.NONE);

                    // Stencil depends on culling
                    this.commitStencilState();
                }
                break;
            case GL_STENCIL_TEST:
                if (this._contextEnableStencil) {
                    this._contextEnableStencil = false;
                    this.commitStencilState();
                }
                break;
            case GL_SCISSOR_TEST:
                if (this._contextEnableScissor) {
                    this._contextEnableScissor = false;
                    this.context.setScissorRectangle(new Rectangle(0, 0, _contextWidth, _contextHeight));
                }
                break;
            case GL_ALPHA_TEST:
                this._contextEnableAlphaTest = false;
                break;
            case GL_BLEND:
                this._contextEnableBlending = false;
                if (!this.disableBlending)
                    this.context.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
                break;
            case GL_TEXTURE_GEN_S:
                this._enableTexGenS = false;
                break;
            case GL_TEXTURE_GEN_T:
                this._enableTexGenT = false;
                break;
            case GL_CLIP_PLANE0:
            case GL_CLIP_PLANE1:
            case GL_CLIP_PLANE2:
            case GL_CLIP_PLANE3:
            case GL_CLIP_PLANE4:
            case GL_CLIP_PLANE5:
                const clipPlaneIndex:int = cap - GL_CLIP_PLANE0;
                this._clipPlaneEnabled[clipPlaneIndex] = false;
                this.clearGLState(ENABLE_LIGHT_OFFSET + clipPlaneIndex);
                break;
            case GL_TEXTURE_2D:
                this._contextEnableTextures[this._activeTextureUnit] = false;
                /* contextEnableTextures = false */
                this.clearGLState(ENABLE_TEXTURE_OFFSET);
                break;
            case GL_LIGHTING:
                this._contextEnableLighting = false;
                this.clearGLState(ENABLE_LIGHTING_OFFSET);
                break;
            case GL_COLOR_MATERIAL:
                this._contextColorMaterial = false; // default is GL_FRONT_AND_BACK and GL_AMBIENT_AND_DIFFUSE
                this.clearGLState(ENABLE_COLOR_MATERIAL_OFFSET);
                break;
            case GL_LIGHT0:
            case GL_LIGHT1:
            case GL_LIGHT2:
            case GL_LIGHT3:
            case GL_LIGHT4:
            case GL_LIGHT5:
            case GL_LIGHT6:
            case GL_LIGHT7:
                var lightIndex:int = cap - GL_LIGHT0;
                this._lightsEnabled[lightIndex] = false;
                this.clearGLState(ENABLE_LIGHT_OFFSET + lightIndex);
                break;
            case GL_POLYGON_OFFSET_FILL:
                this._contextEnablePolygonOffset = false;
                this.clearGLState(ENABLE_POLYGON_OFFSET);
                break;
            default:
                if (log) log.send("[ERROR] Unsupported cap for glDisable: 0x" + cap.toString(16));
        }
    }

    [Internal]
    public function glPushAttrib(mask:uint):void {
        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glPushAttrib + 0x" + mask.toString(16));
        }

        if (Boolean(mask & GL_LIGHTING_BIT)) {
            this.pushCurrentLightingState();
        }

        CONFIG::debug {
            var bits:String = null;

            for (var i:int = 0; i < GL_ATTRIB_BIT.length; i++) {
                if (Boolean(mask & (1 << i)))
                    bits = bits + ", " + GL_ATTRIB_BIT[i];
            }

            if (log) log.send("[NOTE] Unsupported attrib bits " + bits + " for glPushAttrib")
        }
    }

    [Internal]
    public function glPopAttrib():void {
        // only lighting state for now.
        this.popCurrentLightingState()
    }

    [Inline]
    final private function pushCurrentLightingState():void {
        var lState:LightingState = new LightingState();
        lState.enableColorMaterial = this._contextColorMaterial;
        lState.enableLighting = this._contextEnableLighting;
        lState.lightsEnabled = this._lightsEnabled.concat();

        var newLights:Vector.<Light> = new Vector.<Light>(8);
        var lightsLength:int = this._lights.length;
        for (var i:int = 0; i < lightsLength; i++) {
            var l:Light = this._lights[i];
            newLights[i] = (l) ? l.createClone() : null;
        }

        lState.lights = newLights;
        lState.contextMaterial = this._contextMaterial.createClone();
        _lightingStates.push(lState);
    }

    [Inline]
    final private function popCurrentLightingState():void {
        var lState:LightingState = _lightingStates.pop();
        if (lState == null) {
            CONFIG::debug {
                if (log) log.send("[WARNING] Calling popCurrentLightingState with lighting state");
            }
            return;
        }
        this._contextColorMaterial = lState.enableColorMaterial;
        this._contextEnableLighting = lState.enableLighting;
        this._lightsEnabled = lState.lightsEnabled;
        this._lights = lState.lights;
        this._contextMaterial = lState.contextMaterial;
    }

    [Internal]
    public function glTexEnvf(target:uint, pname:uint, param:Number):void {
        if (!_activeTexture) {
            CONFIG::debug {
                if (log) log.send("[WARNING] Calling glTexEnvf with no active texture");
            }
            return;
        }

        const textureParams:TextureParams = _activeTexture.params;
        CONFIG::debug {
            if (log) log.send("[WARNING] Calling glTexEnvf with unsupported pname 0x" + pname.toString(16) + ", " + param);
        }
        switch (pname) {
            case GL_TEXTURE_ENV_MODE:
                textureParams.GL_TEXTURE_ENV_MODE = param;
                break;
            default: {
                CONFIG::debug {
                    if (log) log.send("[WARNING] Calling glTexEnvf with unsupported pname 0x" + pname.toString(16) + ", " + param);
                }
            }
        }
    }

    [Internal]
    public function glTexParameterf(target:uint, pname:uint, param:Number):void {
        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glTexParameterf 0x" + target.toString(16) + " 0x" + pname.toString(16) + " 0x" +
                    param.toString(16) + "\n");
        }

        if (!this._activeTexture) {
            CONFIG::debug {
                if (log) log.send("[WARNING] Calling glTexParameterf with no active texture");
            }
            return;
        }

        const textureParams:TextureParams = _activeTexture.params;

        switch (pname) {
            case GL_TEXTURE_MIN_LOD:
                textureParams.GL_TEXTURE_MIN_LOD = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_MIN_LOD to: 0x" + param.toString(16));
                }
                break;
            case GL_TEXTURE_MAX_LOD:
                textureParams.GL_TEXTURE_MAX_LOD = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_MAX_LOD to: 0x" + param.toString(16));
                }
                break;
            case GL_TEXTURE_MIN_FILTER:
                textureParams.GL_TEXTURE_MIN_FILTER = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_MIN_FILTER to: 0x" + param.toString(16));
                }
                break;
            case GL_TEXTURE_MAG_FILTER:
                textureParams.GL_TEXTURE_MAG_FILTER = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_MAG_FILTER to: 0x" + param.toString(16));
                }
                break;
            default: {
                CONFIG::debug {
                    if (log) log.send("[ERROR] Unsupported pname 0x" + pname.toString(16) + " for glTexParameterf" +
                            (target == GL_TEXTURE_2D ? "(2D)" : "(Cube)"));
                }
            }
        }
    }

    [Internal]
    public function glTexParameteri(target:uint, pname:uint, param:int):void {
        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glTexParameteri 0x" + target.toString(16) + " 0x" + pname.toString(16) + " 0x" +
                    param.toString(16) + "\n");
        }

        if (!this._activeTexture) {
            CONFIG::debug {
                if (log) log.send("[WARNING] Calling glTexParameteri with no active texture");
            }
            return;
        }

        var textureParams:TextureParams = _activeTexture.params;

        switch (pname) {
            case GL_TEXTURE_MAX_ANISOTROPY_EXT:
                textureParams.GL_TEXTURE_MAX_ANISOTROPY_EXT = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_MAX_ANISOTROPY_EXT to: 0x" + param.toString(16));
                }
                break;
            case GL_TEXTURE_MAG_FILTER:
                textureParams.GL_TEXTURE_MAG_FILTER = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_MAG_FILTER to: 0x" + param.toString(16));
                }
                break;
            case GL_TEXTURE_MIN_FILTER:
                textureParams.GL_TEXTURE_MIN_FILTER = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_MIN_FILTER to: 0x" + param.toString(16));
                }
                break;
            case GL_TEXTURE_WRAP_S:
                textureParams.GL_TEXTURE_WRAP_S = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_WRAP_S to: 0x" + param.toString(16));
                }
                break;
            case GL_TEXTURE_WRAP_T:
                textureParams.GL_TEXTURE_WRAP_T = param;
                CONFIG::debug {
                    if (log) log.send("Setting GL_TEXTURE_WRAP_S to: 0x" + param.toString(16));
                }
                break;
            default: {
                CONFIG::debug {
                    if (log) log.send("[NOTE] Unsupported pname 0x" + pname.toString(16) + " for glTexParameteri" +
                            (target == GL_TEXTURE_2D ? "(2D)" : "(Cube)"));
                }
            }
        }
    }

    final private function pixelTypeToString(type:uint):String {
        if (type == GL_BITMAP)
            return PIXEL_TYPE[type - GL_BITMAP];
        else if (type <= GL_FLOAT)
            return PIXEL_TYPE[type - GL_BYTE];
        else if (type <= GL_BGRA)
            return PIXEL_TYPE[type - GL_BGR];
        else
            return PIXEL_TYPE[type - GL_UNSIGNED_BYTE_3_3_2];
    }

    final private function convertPixelDataToBGRA(width:int, height:int, srcFormat:uint, src:ByteArray, srcOffset:uint):ByteArray {
        CONFIG::debug {
            if (log) log.send("convertPixelDataToBGRA: w " + width + " h " + height + " format 0x" + srcFormat.toString(16));
        }

        //var srcBytesPerPixel:int
        var pixelCount:int = width * height;
        var dst:ByteArray = new ByteArray();
        dst.length = pixelCount * 4; // BGRA is 4 bytes

        var originalPosition:uint = src.position;
        src.position = srcOffset;

        var b:int = 0;
        var g:int = 0;
        var r:int = 0;
        var a:int = 0xFF; // fully opaque by default (for conversions from formats that don't have alpha)

        try {
            for (var i:int = 0; i < pixelCount; i++) {
                switch (srcFormat) {
                    case GL_RGBA:
                        r = src.readByte();
                        g = src.readByte();
                        b = src.readByte();
                        a = src.readByte();
                        break;
                    case GL_RGB:
                        r = src.readByte();
                        g = src.readByte();
                        b = src.readByte();
                        break;
                    case GL_LUMINANCE:
                        // if (log) log.send("[Debug] <GL_LUMINANCE> width: " + width + ", height: " + height + ", pixel-len: " + src.bytesAvailable);
                        a = src.readByte();
                        r = a; // = 0 ?
                        g = a; // = 0 ?
                        b = a; // = 0 ?
                        // if (log) log.send("[Debug] <GL_LUMINANCE> alpha: " + a);
                        break;
                    default: {
                        CONFIG::debug {
                            if (log) log.send("[Warning] Unsupported texture format: " + PIXEL_FORMAT[srcFormat - GL_COLOR_INDEX]);
                        }
                        src.position = originalPosition;
                        return dst;
                    }
                }

                // BGRA
                dst.writeByte(b);
                dst.writeByte(g);
                dst.writeByte(r);
                dst.writeByte(a);
            }
        } catch (e:Error) {
            CONFIG::debug {
                if (log) log.send("[ERROR] Error converting pixel to BGRA: " + e.message);
            }
        }

        // restore the position so the function doesn't have side-effects
        src.position = originalPosition;
        return dst;
    }

    [Internal]
    public function glTexSubImage2D(target:uint, level:int, xoff:int, yoff:int, width:int, height:int, format:uint, imgType:uint, ptr:uint, ram:ByteArray):void {
        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glTexSubImage2D 0x" + target.toString(16) + " l:" + level + " " + xoff + " " + yoff + " " + width + "x" + height +
                    PIXEL_FORMAT[format - GL_COLOR_INDEX] + " " + pixelTypeToString(imgType) + " 0x" + ptr.toString(16) + "\n");
        }

        if (this._activeTexture && this._activeTexture.texture) {
            if (this._activeTexture.texture != this.NULL_TEXTURE)
                this._activeTexture.texture.dispose();

            const activeSamplerID:uint = _textureSamplerIDs[_activeTextureUnit];
            this._textures[activeSamplerID] = null;
            this.glBindTexture(target, activeSamplerID);
        }

        this.glTexImage2D(target, level, format, width, height, 0, format, imgType, ptr, ram);
    }

    [Internal]
    public function glTexImage2D(target:uint, level:int, intFormat:int, width:int, height:int, border:int, format:uint, imgType:uint, ptr:uint, ram:ByteArray):void {
        CONFIG::debug {
            if (log)
                log.send("[IMPLEMENTED] glTexImage2D 0x" + target.toString(16) + " texid: " + _textureSamplerIDs[_activeTextureUnit] +
                        " l:" + level + " " + intFormat + " " + width + "x" + height + " b:" + border + " " +
                        PIXEL_FORMAT[format - GL_COLOR_INDEX] + " " + pixelTypeToString(imgType) + " " +
                        imgType.toString(16) + "\n");
        }

        if (intFormat == GL_LUMINANCE) {
            // Unsupported. TODO - Squelch all PF_G8 textures.
            // width = width/2
            // height = height/2
        }

        if (width == 0 || height == 0)
            return;

        var data:ByteArray;
        var dataOffset:uint;
        // XXX: More format to handle.
        // format avaiables:
        // intFormat                format                  imgType
        // GL_ALPHA8                GL_ALPHA                GL_UNSIGNED_BYTE
        // GL_LUMINANCE8            GL_LUMINANCE            GL_UNSIGNED_BYTE
        // GL_LUMINANCE8_ALPHA      GL_LUMINANCE_ALPHA      GL_UNSIGNED_BYTE
        // GL_RGBA4                 GL_LUMINANCE_ALPHA      GL_UNSIGNED_BYTE
        // GL_BGR                   GL_BGR                  GL_UNSIGNED_BYTE
        // GL_RGB8                  GL_RGB                  GL_UNSIGNED_BYTE
        // GL_RGB8                  GL_RGB                  GL_UNSIGNED_SHORT_5_6_5
        // GL_RGB5_A1               GL_RGBA                 GL_UNSIGNED_SHORT_5_5_5_1
        // GL_RGBA8                 GL_RGBA                 GL_UNSIGNED_BYTE
        // GL_RGBA8                 GL_RGBA                 GL_UNSIGNED_INT_8_8_8_8
        // GL_RGBA8                 GL_BGRA                 GL_UNSIGNED_INT_8_8_8_8
        // GL_BGRA                  GL_BGRA                 GL_UNSIGNED_BYTE
        // GL_DEPTH_COMPONENT       GL_DEPTH_COMPONENT      GL_UNSIGNED_BYTE
        // GL_DEPTH_COMPONENT16     GL_DEPTH_COMPONENT      GL_UNSIGNED_SHORT
        // GL_DEPTH_COMPONENT24     GL_DEPTH_COMPONENT      GL_UNSIGNED_INT

        if (ptr > 0 && format != GL_BGRA) { // BGRA_PACKED, BGR_PACKED, etc
            CONFIG::debug {
                if (log2) log2.send("[IMPLEMENTED] glTexImage2D: Converting to BGRA");
            }
            // Convert the texture format
            data = convertPixelDataToBGRA(width, height, format, ram, ptr);
            dataOffset = 0;
        }
        else {
            data = ram;
            dataOffset = ptr;
        }

        this._activeTexture.format = Context3DTextureFormat.BGRA; // Only support BGRA just now for uncompressed format.
        this._activeTexture.compressed = false;

        // Create appropriate texture type and upload data.
        if (target == GL_TEXTURE_2D) {
            this.create2DTexture(width, height, level, data, dataOffset);
        }
        else if (target >= GL_TEXTURE_CUBE_MAP_POSITIVE_X && target <= GL_TEXTURE_CUBE_MAP_NEGATIVE_Z) {
            this.createCubeTexture(width, target, level, data, dataOffset);
        }
        else {
            CONFIG::debug {
                if (log2) log2.send("[ERROR] Unsupported texture type 0x" + target.toString(16) + " for glTexImage2D");
            }
        }
    }

    [Internal]
    public function glCompressedTexImage2D(target:uint, level:int, intFormat:uint, width:int, height:int, border:int, imageSize:int, ptr:uint, ram:ByteArray):void {
        CONFIG::debug {
            if (log2)
                log2.send("[IMPLEMENTED] glCompressedTexImage2D 0x" + target.toString(16) + " texid: " +
                        _textureSamplerIDs[_activeTextureUnit] + " l:" + level + " " + intFormat + " " + width + "x" +
                        height + " b:" + border + " " + imageSize + " " + ptr);
        }
        // Create appropriate texture type and upload data.
        // ATF format:
        //      RGBA
        //      COMPRESSED
        //      COMPRESSED_ALPHA
        var format:String;
        switch (intFormat) {
            case GL_COMPRESSED_RGB_S3TC_DXT1_EXT:
                format = Context3DTextureFormat.COMPRESSED;
                break;
            case GL_COMPRESSED_RGBA_S3TC_DXT1_EXT:
            case GL_COMPRESSED_RGBA_S3TC_DXT3_EXT:
            case GL_COMPRESSED_RGBA_S3TC_DXT5_EXT:
                format = "compressedAlpha"; // explicit string for compatibility.
                break;
            default: {
                CONFIG::debug {
                    if (log) log.send("[ERROR] Unsupported format describes as ATF data.");
                }
            }
            case GL_BGRA:
                format = Context3DTextureFormat.BGRA;
                break;
        }

        this._activeTexture.format = format;
        this._activeTexture.compressed = true;

        if (target == GL_TEXTURE_2D)
            this.create2DTexture(width, height, level, ram, ptr, imageSize, format, true);
        else if (target >= GL_TEXTURE_CUBE_MAP_POSITIVE_X && target <= GL_TEXTURE_CUBE_MAP_NEGATIVE_Z)
            this.createCubeTexture(width, target, level, ram, ptr, imageSize, format, true);
        else {
            CONFIG::debug {
                if (log) log.send("[ERROR] Unsupported texture type 0x" + target.toString(16) +
                        " for glCompressedTexImage2D");
            }
        }

        // correct the miplevels, parsing the ATF data, querying the miplevel instead.
        var oldPos:int = ram.position;
        var idx:int = ptr;
        var numTextures:uint = 0;
        ram.position = idx + 6;
        if ( ram.readUnsignedByte() == 255) {
            idx += 12; // new file version.
        } else {
            idx += 6; // old file version.
        }

        idx += 3;
        ram.position = idx;
        numTextures = ram.readUnsignedByte();

        var b5:int, b6:int;
        ram.position = ptr + 5;
        b5 = ram.readUnsignedByte();
        b6 = ram.readUnsignedByte();

        if (b5 != 0 && b6 == 255) {
            if ((b5 & 0x01) == 1) { // nomip
                numTextures = 1;
            } else {
                numTextures = b5 >> 1 & 0x7f;
            }
        }

        ram.position = oldPos;

        this._activeTexture.mipLevels = numTextures;
    }

    // Returns index of first texture, guaranteed to be contiguous
    [Internal]
    public function glGenTextures(length:uint):uint {
        const result:uint = this._texID;
        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glGenTextures " + length + ", returning ID = [ " + result + ", " + (result
                        + length - 1) + " ]\n");
        }
        for (var i:int = 0; i < length; i++) {
            _textures[_texID] = new TextureInstance(); // FIXME: pooled TextureInstance
            _textures[_texID].texID = this._texID;
            this._texID++;
        }
        return result;
    }

    [Internal]
    public function glDeleteTexture(texid:uint):void {
        if (_textures[texid] == null) {
            CONFIG::debug {
                if (log) log.send("[WARNING] glDeleteTexture called on non-existant texture " + texid + "\n");
            }
            return;
        }

        CONFIG::debug {
            if (log) log.send("[IMPLEMENTED] glDeleteTexture called for " + texid + "\n");
        }

        // Dispose texture instance.
        if (_textures[texid].texture)
            _textures[texid].texture.dispose();

        if (_textures[texid].cubeTexture)
            _textures[texid].cubeTexture.dispose();

        _textures[texid] = null; // TODO: fix things so we can eventually reuse textureIDs
    }

    [Internal]
    public function glGenFramebuffers(length:uint):uint {
        const result:uint = this._framebufferID;
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glGenFramebuffers " + length + ", returning ID = [ " + result + ", " +
                    (result + length - 1) + " ]\n");
        }
        for (var i:int = 0; i < length; i++) {
            this._framebuffers[_framebufferID] = new FramebufferInstance(); // FIXME: Pooled framebuffer ?
            this._framebuffers[_framebufferID].id = this._framebufferID;
            this._framebufferID++;
        }
        return result;
    }

    [Internal]
    public function glDeleteFramebuffers(length:uint, ptr:int):void {
        CONFIG::debug {
            if (log2)
                log2.send("[IMPLEMENTED] glDeleteFramebuffers " + length + ", from ptr = 0x" + ptr.toString(16));
        }

        for (var i:int = 0; i < length; ++i) {
            var id:int = CModule.read32(ptr + i * 4);
            if (!(id in this._framebuffers))
                continue;
            var buffer:FramebufferInstance = this._framebuffers[id];
            // TODO: dispose the framebuffer.
            delete this._framebuffers[id];
        }
    }

    [Internal]
    public function glIsFramebuffer(framebuffer:uint):Boolean {
        return framebuffer in this._framebuffers;
    }

    [Internal]
    public function glBindFramebuffer(target:uint, framebuffer:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glBindFramebuffer 0x" + target.toString(16) + " " + framebuffer + "\n");
        }

        if (framebuffer != 0) {
            this._activeFramebuffer = this._framebuffers[framebuffer];
            if (this._activeFramebuffer.texture) {
                this.context.setRenderToTexture(this._activeFramebuffer.texture.texture);
            }
        }
        else {
            this.context.setRenderToBackBuffer();
        }
    }

    [Internal]
    public function glFramebufferTexture2D(target:uint, attachment:uint, textarget:uint, texture:uint, level:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glFramebufferTexture2D " + target + " " + attachment + " " + textarget +
                    " " + texture + " " + level + "\n");
        }

        this._activeFramebuffer.texture = this._textures[texture];
    }

    [Internal]
    public function glFramebufferRenderbuffer(target:uint, attachment:int, renderbufferTarget:uint, renderbuffer:uint):void {
        CONFIG::debug {
            if (log2)
                log2.send("[NOT IMPLEMENTED] glFramebufferRenderbuffer...");
        }
        // TODO: glFramebufferRenderbuffer.
    }

    [Internal]
    public function glIsRenderbuffer(renderbuffer:uint):Boolean {
        return renderbuffer in this._renderbuffers;
    }

    [Internal]
    public function glGenRenderbuffers(size:uint):uint {
        const result:uint = this._renderbufferID;
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glGenRenderbuffers " + size + ", returning ID = [ " + result + ", " +
                    (result + size - 1) + " ]\n");
        }
        for (var i:int = 0; i < size; i++) {
            this._renderbuffers[this._renderbufferID] = new RenderbufferInstance(); // FIXME: Pooled renderbuffer ?
            this._renderbuffers[this._renderbufferID].id = this._renderbufferID;
            this._renderbufferID++;
        }
        return result;
    }

    [Internal]
    public function glDeleteRenderbuffer(length:uint, ptr:int):void {
        CONFIG::debug {
            if (log2)
                log2.send("[IMPLEMENTED] glDeleteRenderbuffers" + length + ", from ptr = 0x" + ptr.toString(16));
        }

        for (var i:int = 0; i < length; ++i) {
            var id:int = CModule.read32(ptr + i * 4);
            if (!(id in this._renderbuffers))
                continue;
            var buffer:RenderbufferInstance = this._renderbuffers[id];
            // TODO: dispose the renderbuffer.
            delete this._renderbuffers[id];
        }
    }

    [Internal]
    public function glBindRenderbuffer(target:uint, renderbuffer:uint):void {
        CONFIG::debug {
            if (log2)
                log2.send("[IMPLEMENTED] glBindRenderbuffer 0x" + target.toString(16) + " " + renderbuffer);
        }

        this._activeRenderbuffer = this._renderbuffers[renderbuffer];
        // TODO: glBindRenderbuffer.
    }

    // extern void glRenderbufferStorage (GLenum target, GLenum internalformat, GLsizei width, GLsizei height)
    [Internal]
    public function glRenderbufferStorage(target:uint, internalFormat:int, width:uint, height:uint):void {
        CONFIG::debug {
            if (log2)
                log2.send("[IMPLEMENTED] glRenderbufferStorage 0x" + target.toString(16) + " f: 0x" +
                        internalFormat.toString(16) + " WxH: " + width + "x" + height);
        }
        // TODO: glRenderbufferStorage
    }

    [Internal]
    public function glRenderbufferStorageMultisample(target:uint, samples:uint, internalFormat:int, width:uint, height:uint):void {
        CONFIG::debug {
            if (log2)
                log2.send("[IMPLEMENTED] glRenderbufferStorageMultisample 0x" + target.toString(16) + " f: 0x" +
                        internalFormat.toString(16) + " WxH: " + width + "x" + height + " s:" + samples);
        }
        // TODO: glRenderbufferStorageMultisample
    }

    [Internal]
    public function glIsShader(shader:uint):Boolean {
        return (shader in _shaders);
    }

    [Internal]
    public function glCreateShader(type:uint):uint {
        const result:uint = this._shaderID;

        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glCreateShader 0x" + type.toString(16) + " ID: " + result + "\n");
        }

        _shaders[_shaderID] = new ShaderInstance(); // FIXME: Pooled ?
        _shaders[_shaderID].id = this._shaderID;
        _shaders[_shaderID].type = type;
        _shaderID++;

        return result;
    }

    [Internal]
    public function glShaderSource(shader:uint, json:String):void {
        CONFIG::debug {
            if (log2) log2.send("Parsing \"" + json + "\"");
        }

        var obj:Object = JSON.parse(json);

        CONFIG::debug {
            const source:String = obj["agalasm"];
            if (log2) log2.send("[IMPLEMENTED] glShaderSource(#agalVersion " + this._agalVersion + ") \n" + source);
        }

        var shaderInstance:ShaderInstance = _shaders[shader];
        shaderInstance.json = obj;
    }

    [Internal]
    public function glCompileShader(shader:uint):void {
        // We compile the shader source later in glLinkProgram actually, need to sync varyings.
        void(shader);
    }

    [Internal]
    public function glIsProgram(program:uint):Boolean {
        return (program in _programs);
    }

    [Internal]
    public function glCreateProgram():uint {
        const result:uint = this._programID;

        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glCreateProgram ID: " + result + "\n");
        }

        this._programs[this._programID] = new ProgramInstance(); // FIXME: pooled ?
        this._programs[this._programID].id = this._programID;
        this._programs[this._programID].program = this.context.createProgram();
        this._programID++;

        return result;
    }

    [Internal]
    public function glAttachShader(program:uint, shader:uint):void {
        var programInstance:ProgramInstance = _programs[program];
        var shaderInstance:ShaderInstance = _shaders[shader];

        if (shaderInstance.type == GL_VERTEX_SHADER)
            programInstance.vertexShader = shaderInstance;
        else
            programInstance.fragmentShader = shaderInstance;
    }

    [Internal]
    public function glGetAttribLocation(program:uint, name:String):int {
        var programInstance:ProgramInstance = _programs[program];
        var op:String = programInstance.vertexShader.json["varnames"][name];
        if (op) {
            var index:int = -1;
            var opIndex:uint = uint(op.substr(2)); // vaX
            for (var i:* in programInstance.attribMap) {
                if (programInstance.attribMap[i] == opIndex) {
                    // found.
                    index = int(i);
                }
            }

            if (index == -1)
                return opIndex;
        }

        return -1;
    }

    [Internal]
    public function glBindAttribLocation(program:uint, index:uint, name:String):void {
        var programInstance:ProgramInstance = _programs[program];

        var op:String = programInstance.vertexShader.json["varnames"][name];
        if (op) {
            var opIndex:uint = uint(op.substr(2));
            programInstance.attribMap[index] = opIndex;
            CONFIG::debug {
                if (log2) log2.send("glBindAttribLocation " + index + " : " + name + " -> " + op + " -> " + opIndex);
            }
        }
        else {
            CONFIG::debug {
                if (log2) log2.send("glBindAttribLocation " + index + " : " + name + " -> " + op);
            }
        }
    }

    [Inline]
    static private function getVertexBufferFormat(elementSize:uint):String {
        if (elementSize == 4 * 1) return Context3DVertexBufferFormat.FLOAT_1;
        if (elementSize == 4 * 2) return Context3DVertexBufferFormat.FLOAT_2;
        if (elementSize == 4 * 3) return Context3DVertexBufferFormat.FLOAT_3;
        if (elementSize == 4 * 4) return Context3DVertexBufferFormat.FLOAT_4;

        return null; // should not run here.
    }

    [Internal]
    public function setVertexData(index:uint, format:uint, data:ByteArray, dataPtr:uint, size:uint, elementSize:uint):void {
        var vertices:VertexBuffer3D = context.createVertexBuffer(size / elementSize, elementSize / 4);
        vertices.uploadFromByteArray(data, dataPtr, 0, size / elementSize);

        var agalIndex:uint = this._activeProgramInstance.attribMap[index];

        if (this._activeProgramInstance) {
            CONFIG::debug {
                if (log2) log2.send("setVertexData: Setting vertex data source #" + agalIndex + " to a buffer of " +
                        size + " bytes with " + elementSize + " element size \n");
            }

            var vertexBufferFormat:String = getVertexBufferFormat(elementSize);
            this.context.setVertexBufferAt(agalIndex, vertices, 0, vertexBufferFormat);
        }
        else {
            CONFIG::debug {
                if (log2) log2.send("[WARNING] setVertexData: No active program is in place - the function is no-op\n");
            }
        }
    }

    [Internal]
    public function setVertexBuffer(index:uint, buffer:uint, offset:uint, elementSize:uint):void {
        CONFIG::debug {
            if (log2) log2.send("setVertexBuffer (setting): index: " + index + " buffer: " + buffer + " offset: " +
                    offset + " elementSize: " + elementSize + "\n");
        }

        // We can no resolve agalIndex for specified vertexAttribute without active program
        if (!this._activeProgramInstance) {
            return;
        }

        var bufferInstance:BufferInstance = this._buffers[buffer];
        var agalIndex:uint = this._activeProgramInstance.attribMap[index];
        var vertexBufferFormat:String = getVertexBufferFormat(elementSize);

        // Offset is divided by 4 because Stage3D needs offset in 32-bit words
        // context.setVertexBufferAt(agalIndex, bufferInstance.vertexBuffer, offset / 4, vertexBufferFormat)
        this.context.setVertexBufferAt(index, bufferInstance.vertexBuffer, offset / 4, vertexBufferFormat);

        CONFIG::debug {
            if (log2) log2.send("setVertexBuffer (setted): agalIndex: " + agalIndex + " format: " + vertexBufferFormat +
                    " index: " + index + " buffer: " + buffer + " offset: " + offset + " elementSize: " + elementSize);
        }
    }

    [Internal]
    public function uploadVertexBuffer(buffer:uint, stride:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] uploadVertexBuffer uploading buffer: " + buffer + "\n");
        }

        var bufferInstance:BufferInstance = this._buffers[buffer];
        if (!bufferInstance.uploaded) {
            bufferInstance.stride = stride;
            var vertexCount:uint = bufferInstance.size / bufferInstance.stride;

            bufferInstance.stride = stride;
            bufferInstance.vertexBuffer = this.context.createVertexBuffer(vertexCount, bufferInstance.stride / 4);

            // In Stage3D vertex buffer should fully uploaded at least once
            var missingBytes:uint = vertexCount * bufferInstance.stride - bufferInstance.data.length;
            for (var i:uint = 0; i < missingBytes; i++) {
                bufferInstance.data.writeByte(0);
            }

            bufferInstance.vertexBuffer.uploadFromByteArray(bufferInstance.data, 0, 0,
                    bufferInstance.data.length / bufferInstance.stride);
            bufferInstance.data = null;
            bufferInstance.uploaded = true;
            CONFIG::debug {
                if (log2) log2.send("[IMPLEMENTED] uploadVertexBuffer uploaded buffer: " + buffer + "\n");
            }
        }
    }

    [Internal]
    public function clearVertexBuffer(index:uint):void {
        //var agalIndex:uint = this._activeProgramInstance.attribMap[index];
        context.setVertexBufferAt(index, null);
    }

    /* @private */
    private var _indexBuffer:IndexBuffer3D = null;

    [Internal]
    public function setIndexBuffer(data:ByteArray, dataPtr:uint, indexCount:uint) { // ???
        CONFIG::debug {
            if (log2) log2.send("setIndexBuffer data: " + data.length + " dataPtr: " + dataPtr + " indexCount: " +
                    indexCount + "\n");
        }

        var stubSize:uint = 5000;
        _indexBuffer = context.createIndexBuffer(stubSize);//indexCount)
        // var tmp:Vector.<uint> = new Vector.<uint>();
        // for (var i:uint = 0; i < stubSize; i++) {
            // tmp.push(0);
        // }
        // _indexBuffer.uploadFromVector(tmp, 0, stubSize);
        var tmp:ByteArray = new ByteArray();
        tmp.endian = "littleEndian";
        tmp.length = stubSize * 4;
        _indexBuffer.uploadFromByteArray(tmp, 0, 0, tmp.length);
        _indexBuffer.uploadFromByteArray(data, dataPtr, 0, indexCount);
    }

    [Internal]
    public function clearIndexBuffer() {
        _indexBuffer = null;
    }

    [Internal]
    public function glDrawTriangles(vertexCount:uint, stripe:Boolean) {
        if (this._activeElementArrayBuffer == null && this._indexBuffer == null) {
            CONFIG::debug {
                if (log2) log2.send("glDrawTriangles: Generating index buffer.\n");
            }

            var indexValues:Vector.<uint> = null;
            var indexCount:uint = 0;
            var i:uint = 0;

            if (!stripe) {
                indexCount = vertexCount;
                this._indexBuffer = this.context.createIndexBuffer(indexCount);
                indexValues = new Vector.<uint>();

                for (i = 0; i < vertexCount; i++) {
                    indexValues.push(i);
                }
            }
            else {
                CONFIG::debug {
                    if (log2) log2.send("Drawing stripe\n");
                }

                indexCount = 3 * (vertexCount - 2);
                this._indexBuffer = this.context.createIndexBuffer(indexCount);
                indexValues = new Vector.<uint>();

                for (i = 0; i < vertexCount - 2; i++) {
                    indexValues.push(i + 0);
                    indexValues.push(i + 1);
                    indexValues.push(i + 2);
                }
            }

            CONFIG::debug {
                if (log2) log2.send("glDrawTriangles: Drawing " + indexCount / 3 + " triangles\n");
            }

            this._indexBuffer.uploadFromVector(indexValues, 0, indexCount);
        }

        // Defered to set program.
        const programInstance:ProgramInstance = this._activeProgramInstance;
        if ( programInstance && !programInstance.uploaded ) {
            this._agalAssembler.assemble(Context3DProgramType.VERTEX, programInstance.vertexShader.agalasm,
                    this._agalVersion);
            programInstance.vertexShader.agalcode = this._agalAssembler.agalcode;

            this._agalAssembler.assemble(Context3DProgramType.FRAGMENT, programInstance.fragmentShader.agalasm,
                    this._agalVersion);
            programInstance.fragmentShader.agalcode = this._agalAssembler.agalcode;

            try {
                programInstance.program.upload(programInstance.vertexShader.agalcode,
                        programInstance.fragmentShader.agalcode);

                programInstance.uploaded = true;
            }
            catch (e:Error) {
                CONFIG::debug {
                    log2 && log2.send("Program Link Error: " + e.errorID + " " + e.message + "\n" + e.getStackTrace());
                }
                throw e;
            }
        }

        if ( programInstance )
            this.context.setProgram( programInstance.program );
        else
            throw new Error("No active program set to call glDrawTriangles!");

        CONFIG::debug {
            if (log2) log2.send("Going to draw " + (vertexCount / 3) + " triangles\n");
        }

        if (this._activeElementArrayBuffer != null) {
            this.context.drawTriangles(this._activeElementArrayBuffer.indexBuffer, 0, vertexCount / 3);
        }
        else {
            this.context.drawTriangles(this._indexBuffer, 0, vertexCount / 3);
        }
    }

    [Internal]
    public function glLinkProgram(program:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glLinkProgram from " + program + "\n");
        }

        var programInstance:ProgramInstance = _programs[program];

        // NOTE: The agalcode both of vertex and fragment shaders should be null now.
        // NOTE: Resolve the fragment shader's varying opCode index correct to
        // vertex shader's varying opCode index..

        var vertSource:String = programInstance.vertexShader.json["agalasm"];
        var fragSource:String = programInstance.fragmentShader.json["agalasm"];
        var fragVarnames:Object = programInstance.fragmentShader.json["varnames"];
        var vertVarnames:Object = programInstance.vertexShader.json["varnames"];

        var replaceVars:Object = {};
        var matches:Array;

        for (var fvKey:* in fragVarnames) {
            if ((matches = fragVarnames[fvKey].match(/v\d+/) || []).length > 0) {
                // varying found.
                // must be in the vertVarnames.
                if (vertVarnames[fvKey] == fragVarnames[fvKey])
                    continue;
                replaceVars[fragVarnames[fvKey]] = vertVarnames[fvKey];
            }
        }

        var replaced:Boolean;
        for (var rk:* in replaceVars) {
            CONFIG::debug {
                if (log2) log2.send("Syncing fragment shader's varying " + rk + " into vertex shader's varying " +
                        replaceVars[rk] + "\n");
            }
            fragSource = fragSource.replace(new RegExp(rk, 'g'), replaceVars[rk]);
            replaced = true;
        }

        CONFIG::debug {
            if (replaced && log2) {
                log2.send("Post processing fragment shader's source: \n" + fragSource + "\n");
            }
        }

        programInstance.vertexShader.agalasm = vertSource;
        programInstance.fragmentShader.agalasm = fragSource;
        programInstance.uploaded = false;

        if (programInstance.fragmentSamplerStates)
            programInstance.fragmentSamplerStates.length = 0;
        else
            programInstance.fragmentSamplerStates = new Vector.<FragmentSamplerState>();
    }

    static private function getSamplerFormatFlag(textureInstance:TextureInstance):String {
        if (textureInstance.compressed) {
            if (textureInstance.format == 'compressed') {
                return 'dxt1';
            } else if (textureInstance.format == 'compressedAlpha') {
                return 'dxt5';
            }
        }
        return null;
    }

    static private function getSamplerStateFlags(texture:TextureInstance):Array {
        var wrap:String = "clamp";
        var filter:String = "nearest";
        var mipFilter:String = "mipnone";

        if (texture.params.GL_TEXTURE_WRAP_S == GL_REPEAT) {
            wrap = "repeat";
        }
        else if (texture.params.GL_TEXTURE_WRAP_S == GL_CLAMP) {
            wrap = "clamp";
        }

        if (texture.params.GL_TEXTURE_WRAP_S != texture.params.GL_TEXTURE_WRAP_T) {
            wrap += "_u_";
            if (texture.params.GL_TEXTURE_WRAP_T == GL_REPEAT) {
                wrap += "repeat_v";
            }
            else {
                wrap += "clamp_v";
            }
        }

        if (texture.params.GL_TEXTURE_MAX_ANISOTROPY_EXT > 0) {
            filter = "anisotropic" + texture.params.GL_TEXTURE_MAX_ANISOTROPY_EXT + 'x';
        } else if (texture.params.GL_TEXTURE_MIN_FILTER == GL_LINEAR ||
                texture.params.GL_TEXTURE_MIN_FILTER == GL_LINEAR_MIPMAP_LINEAR ||
                texture.params.GL_TEXTURE_MIN_FILTER == GL_LINEAR_MIPMAP_NEAREST) {
            filter = "linear";
        }

        if (texture.mipLevels > 1) {
            if (texture.params.GL_TEXTURE_MIN_FILTER == GL_LINEAR_MIPMAP_LINEAR ||
                    texture.params.GL_TEXTURE_MIN_FILTER == GL_NEAREST_MIPMAP_LINEAR) {
                mipFilter = "miplinear";
            }
            else {
                mipFilter = "mipnearest";
            }
        }

        return [wrap, filter, mipFilter];
    }

    [Inline]
    final private function get deferredSamplerStateSupported():Boolean {
        return 'setSamplerStateAt' in this.context;
    }

    /* @private */
    protected function setSamplerState(sampler:uint, texture:TextureInstance):void {
        var programInstance:ProgramInstance = this._activeProgramInstance;
        if (!programInstance)
            return;

        var fragmentSamplerStates:Vector.<FragmentSamplerState> = programInstance.fragmentSamplerStates;
        if (fragmentSamplerStates.length <= sampler)
            fragmentSamplerStates.length = sampler + 1;

        var samplerState:FragmentSamplerState = fragmentSamplerStates[sampler];
        if (!samplerState) {
            samplerState = new FragmentSamplerState();
            fragmentSamplerStates[sampler] = samplerState;
        }

        var formatDirty:Boolean = samplerState.compressed != texture.compressed || samplerState.format != texture.format;
        var statesDirty:Boolean = samplerState.key != texture.key;
        var shaderModified:Boolean = false;

        if (!formatDirty && statesDirty && this.deferredSamplerStateSupported) {
            // don't replace the shader, just set the sampler state later before drawing.
            shaderModified = false;
        } else if (formatDirty || statesDirty) {
            // modified the shader source.
            shaderModified = true;
        }

        CONFIG::debug {
            if (log2)
                log2.send("[DEBUG] setSamplerState with format dirty " + formatDirty + ", states dirty " + statesDirty,
                        "deferred sampler state setting supported " + this.deferredSamplerStateSupported);
        }

        samplerState.key = texture.key;

        if (formatDirty) {
            samplerState.compressed = texture.compressed;
            samplerState.format = texture.format;
        }

        if (statesDirty)
            samplerState.flags = getSamplerStateFlags(texture);

        if (shaderModified) {
            var agalasm:String = programInstance.fragmentShader.agalasm;
            if (!agalasm) {
                CONFIG::debug {
                    if (log2)
                        log2.send("[ERROR] Not availiable shader ASM found in fragment for sampler states setting fs"
                            + sampler);
                }
                return;
            }

            CONFIG::debug {
                if (log2)
                    log2.send("[NOTE] Going to modified the fragment agalasm for sampler state setting fs" + sampler);
            }

            programInstance.uploaded = false;

            var matches:Array = agalasm.match(new RegExp('fs' + sampler + '\\s*<[\\w,\\s*]+>'));
            if (matches && matches.length > 0) {
                var formatFlag:String = getSamplerFormatFlag(texture);
                var str:String = 'fs' + sampler + ' <2d,';
                if (formatFlag)
                    str += formatFlag + ',';
                str += samplerState.flags.join(',') + '>';
                programInstance.fragmentShader.agalasm = agalasm.replace(matches[0], str);
                CONFIG::debug {
                    if (log2)
                        log2.send("[DEBUG] Setting fs" + sampler + " flags to " + str);
                }
            } else {
                CONFIG::debug {
                    if (log2) {
                        log2.send("[ERROR] Not availiable tex ... fs" + sampler + " <...> found in fragment shader.");
                        log2.send("[DEBUG] matches " + matches ? matches[0] : "");
                    }
                }
            }
        } else if (statesDirty && this.deferredSamplerStateSupported) {
            var func:Function = context['setSamplerStateAt'] as Function;
            const options:Array = samplerState.flags;
            func(sampler, /* wrap */ options[0], /* filter */ options[1], /* mipFilter */ options[2]);
        }
    }

    [Inline]
    static private function isUniformVariable(shaderType:uint, name:String):Boolean {
        return name.charCodeAt(1) == 'c'.charCodeAt(0) || name.charCodeAt(1) == 's'.charCodeAt(0);
    }

    [Internal]
    public function glGetUniformLocation(program:uint, name:String):uint {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glGetUniformLocation from " + program + " @ " + name + " (going to use "
                    + _variableID + ")\n");
        }

        var varID:int = -1;
        var programInstance:ProgramInstance = this._programs[program];

        var constantRegister:String = programInstance.vertexShader.json["varnames"][name];
        if (constantRegister && isUniformVariable(GL_VERTEX_SHADER, constantRegister)) {
            CONFIG::debug {
                if (log2) log2.send("glGetUniformLocation " + program + " : " + name + " found in Vertex Shader @ " +
                        constantRegister + "\n");
            }

            varID = this._variableID++;

            this._variableHandles[varID] = new VariableHandle(); // FIXME: Pooled VariableHandle ?
            this._variableHandles[varID].id = varID;
            this._variableHandles[varID].shader = programInstance.vertexShader;
            this._variableHandles[varID].number = uint(constantRegister.substr(2));
            this._variableHandles[varID].name = constantRegister;

            return varID;
        }

        constantRegister = programInstance.fragmentShader.json["varnames"][name];
        if (constantRegister && isUniformVariable(GL_FRAGMENT_SHADER, constantRegister)) {
            CONFIG::debug {
                if (log2) log2.send("glGetUniformLocation " + program + " : " + name + " found in Fragment Shader @ " +
                        constantRegister + "\n");
            }

            varID = this._variableID++;

            this._variableHandles[varID] = new VariableHandle(); // FIXME: Pooled VariableHandle ?
            this._variableHandles[varID].id = varID;
            this._variableHandles[varID].shader = programInstance.fragmentShader;
            this._variableHandles[varID].number = uint(constantRegister.substr(2));
            this._variableHandles[varID].name = constantRegister;

            return varID;
        }

        // var not found on vertex or fragment shader
        return varID;
    }

    [Internal]
    public function glUniform4f(handle:uint, v0:Number, v1:Number, v2:Number, v3:Number):void {
        var variableHandle:VariableHandle = this._variableHandles[handle];

        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glUniform(1,2,3,4)(f,i) resolved " + handle + " into " +
                    variableHandle.name + " register\n");
        }

        if (variableHandle.name.charCodeAt(0) == 'f'.charCodeAt(0) && variableHandle.name.charCodeAt(1) == 's'.charCodeAt(0)) {
            var texture:TextureInstance = _textureSamplers[uint(v0)];
            CONFIG::debug {
                if (log2) log2.send("[IMPLEMENTED] glUniform(1,2,3,4)(f,i) encountered fsX register - setting texture sampler to TexUnit "
                        + uint(v0) + " which resolves into " + texture.texture + "\n");
            }

            this.context.setTextureAt(variableHandle.number, texture.texture);

            // Sets the sampler state here.
            this.setSamplerState(variableHandle.number, texture);
            return;
        }

        var shaderType:String = variableHandle.shader.type == GL_VERTEX_SHADER ? Context3DProgramType.VERTEX :
            Context3DProgramType.FRAGMENT;
        context.setProgramConstantsFromVector(shaderType, variableHandle.number, Vector.<Number>([v0, v1, v2, v3]));

        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glUniform(1,2,3,4)(f,i) uniform location(" + handle + ") set constants resolved as " +
                    variableHandle.name + "\nregister to opIndex " + variableHandle.number + " width values [" + v0 +
                    "," + v1 + "," + v2 + "," + v3 + "]");
        }
    }

    [Internal]
    public function glUniformMatrix4f(handle:uint, transpose:Boolean, v0:Number, v1:Number, v2:Number, v3:Number, v4:Number, v5:Number, v6:Number, v7:Number, v8:Number, v9:Number, v10:Number, v11:Number, v12:Number, v13:Number, v14:Number, v15:Number):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glUniformMatrix4f with location " + handle + "\n");
        }

        var variableHandle = this._variableHandles[handle];
        var shaderType:String = variableHandle.shader.type == GL_VERTEX_SHADER ? Context3DProgramType.VERTEX :
            Context3DProgramType.FRAGMENT;

        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glUniformMatrix4f setting float4x4 into vc" + variableHandle.number +
                    " for " + shaderType + "\n");
            if (log2) log2.send("[IMPLEMENTED] glUniformMatrix4f value = \n" + v0 + " " + v1 + " " + v2 + " " + v3 + "\n"
                    + v4 + " " + v5 + " " + v6 + " " + v7 + "\n"
                    + v8 + " " + v9 + " " + v10 + " " + v11 + "\n"
                    + v12 + " " + v13 + " " + v14 + " " + v15 + "\n"
                    + "\n");
        }

        context.setProgramConstantsFromMatrix(shaderType, variableHandle.number, new Matrix3D(Vector.<Number>([
            v0, v1, v2, v3,
            v4, v5, v6, v7,
            v8, v9, v10, v11,
            v12, v13, v14, v15
        ])), !transpose);
    }

    [Internal]
    public function glColorMask(red:Boolean, green:Boolean, blue:Boolean, alpha:Boolean):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glColorMask r:" + red + " g:" + green + " b:" + blue + " a:" + alpha);
        }

        this.context.setColorMask(red, green, blue, alpha);
    }

    [Internal]
    public function glUseProgram(program:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glUseProgram " + program + "\n");
        }

        var programInstance:ProgramInstance = this._programs[program];
        // this.context.setProgram(programInstance.program);

        this._activeProgramInstance = programInstance;

        var constantName:String;
        var consts:Object = programInstance.vertexShader.json["consts"];
        for (constantName in consts) {
            CONFIG::debug {
                if (log2) log2.send("[IMPLEMENTED] glUseProgram: Setting vertex const " + constantName + " for " +
                        program + "\n");
            }

            this.context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, uint(constantName.substr(2)),
                    Vector.<Number>(consts[constantName]));
        }

        consts = programInstance.fragmentShader.json["consts"];
        for (constantName in consts) {
            CONFIG::debug {
                if (log2) log2.send("[IMPLEMENTED] glUseProgram: Setting fragment const " + constantName + " for " +
                        program + "\n");
            }
            this.context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, uint(constantName.substr(2)),
                    Vector.<Number>(consts[constantName]));
        }
    }

    final private function stencilOpToContext3DStencilAction(op:uint):String {
        switch (op) {
            case GL_ZERO:
                return Context3DStencilAction.ZERO;
            case GL_KEEP:
                return Context3DStencilAction.KEEP;
            case GL_REPLACE:
                return Context3DStencilAction.SET;
            case GL_INCR:
                return Context3DStencilAction.INCREMENT_SATURATE;
            case GL_DECR:
                return Context3DStencilAction.DECREMENT_SATURATE;
            case GL_INVERT:
                return Context3DStencilAction.INVERT;
            case GL_INCR_WRAP:
                return Context3DStencilAction.INCREMENT_WRAP;
            case GL_DECR_WRAP:
                return Context3DStencilAction.DECREMENT_WRAP;
            default:
                if (log) log.send("[ERROR] Unknown stencil op: 0x" + op.toString(16));
                return null;
        }
    }

    final private function commitStencilState():void {
        if (this._contextEnableStencil) {
            var triangleFace:String = _contextEnableCulling ? glCullModeToContext3DTriangleFace(_glCullMode,
                    !_frontFaceClockWise) : Context3DTriangleFace.FRONT_AND_BACK;
            this.context.setStencilActions(triangleFace,
                    _contextStencilCompareMode,
                    _contextStencilActionPass,
                    _contextStencilActionDepthFail,
                    _contextStencilActionStencilFail);
        }
        else {
            // Reset to default
            this.context.setStencilActions(Context3DTriangleFace.FRONT_AND_BACK,
                    Context3DCompareMode.ALWAYS,
                    Context3DStencilAction.KEEP,
                    Context3DStencilAction.KEEP,
                    Context3DStencilAction.KEEP);
        }
    }

    [Internal]
    public function glStencilOp(fail:uint, zfail:uint, zpass:uint):void {
        CONFIG::debug {
            if (log) log.send("glStencilOp");
        }
        this._contextStencilActionStencilFail = stencilOpToContext3DStencilAction(fail);
        this._contextStencilActionDepthFail = stencilOpToContext3DStencilAction(zfail);
        this._contextStencilActionPass = stencilOpToContext3DStencilAction(zpass);
        this.commitStencilState();
    }

    //extern void glStencilFunc (GLenum func, GLint ref, GLuint mask):void
    [Internal]
    public function glStencilFunc(func:uint, ref:int, mask:uint):void {
        CONFIG::debug {
            if (log) log.send("glStencilFunc");
        }
        this._contextStencilCompareMode = convertCompareMode(func);
        this.context.setStencilReferenceValue(ref, mask, mask);
        this.commitStencilState();
    }

    [Internal]
    public function glScissor(x:int, y:int, width:int, height:int):void {
        CONFIG::debug {
            if (log) log.send("glScissor " + x + ", " + y + ", " + width + ", " + height);
        }

        this._scissorRect = this._scissorRect || new Rectangle;
        this._scissorRect.x = x;
        this._scissorRect.y = y;
        this._scissorRect.width = x + width;
        this._scissorRect.height = y + height;

        if (this._contextEnableScissor)
            this.context.setScissorRectangle(this._scissorRect);
    }

    [Internal]
    public function glViewport(x:uint, y:uint, width:uint, height:uint):void {
        CONFIG::debug {
            if (log2) log2.send("[IMPLEMENTED] glViewport invoked with " + x + ", " + y + ", " + width + ", " + height);
        }
        if (null != this.viewportDelegator) {
            this.viewportDelegator(x, y, width, height);
        }
        else {
            this.context.configureBackBuffer(width, height, 0);
        }
    }

    [Internal]
    public function glDepthRangef(near:Number, far:Number):void {
        // if (log) log.send( "[STUBBED] glDepthRangef " + near + " " + far + "\n")
    }

    [Internal]
    public function glClearDepth(depth:Number):void {
        CONFIG::debug {
            if (log) log.send( "[IMPLEMENTED] glClearDepthf " + depth + "\n");
        }
        this._contextClearDepth = depth;
    }

    [Internal]
    public function glClearStencil(s:int):void {
        CONFIG::debug {
            if (log) log.send( "[IMPLEMENTED] glClearStencil " + s + "\n");
        }
        this._contextClearStencil = s;
    }

    final private function translateBlendFactor(openGLBlendFactor:uint):String {
        if (openGLBlendFactor == GL_ONE) {
            return Context3DBlendFactor.ONE;
        }
        else if (openGLBlendFactor == GL_ZERO) {
            return Context3DBlendFactor.ZERO;
        }
        else if (openGLBlendFactor == GL_SRC_ALPHA) {
            return Context3DBlendFactor.SOURCE_ALPHA;
        }
        else if (openGLBlendFactor == GL_ONE_MINUS_SRC_ALPHA) {
            return Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;
        }
        else if (openGLBlendFactor == GL_DST_ALPHA) {
            return Context3DBlendFactor.DESTINATION_ALPHA;
        }
        else if (openGLBlendFactor == GL_ONE_MINUS_DST_ALPHA) {
            return Context3DBlendFactor.ONE_MINUS_DESTINATION_ALPHA;
        }
        else if (openGLBlendFactor == GL_SRC_COLOR) {
            return Context3DBlendFactor.SOURCE_COLOR;
        }
        else if (openGLBlendFactor == GL_ONE_MINUS_SRC_COLOR) {
            return Context3DBlendFactor.ONE_MINUS_SOURCE_COLOR;
        }
        else if (openGLBlendFactor == GL_DST_COLOR) {
            return Context3DBlendFactor.DESTINATION_COLOR;
        }
        else if (openGLBlendFactor == GL_ONE_MINUS_DST_COLOR) {
            return Context3DBlendFactor.ONE_MINUS_DESTINATION_COLOR;
        }
        return Context3DBlendFactor.ONE;
    }

    [Internal]
    public function glBlendFunc(sourceFactor:uint, destinationFactor:uint):void {
        this._contextSrcBlendFunc = this.translateBlendFactor(sourceFactor);
        this._contextDstBlendFunc = this.translateBlendFactor(destinationFactor);

        CONFIG::debug {
            if (log) log.send("glBlendFunc " + _contextSrcBlendFunc + ", " + _contextDstBlendFunc);
        }

        if (this._contextEnableBlending && !this.disableBlending)
            this.context.setBlendFactors(_contextSrcBlendFunc, _contextDstBlendFunc);
    }

    [Internal]
    public function glBlendFuncSeparate(srcRGB:uint, dstRGB:uint, srcAlpha:uint, dstAlpha:uint):void {
        this._contextSrcBlendFunc = this.translateBlendFactor(srcRGB);
        this._contextDstBlendFunc = this.translateBlendFactor(dstRGB);

        if (srcRGB == GL_ONE && dstRGB == GL_ONE && srcAlpha == GL_ZERO && dstAlpha == GL_ONE) {
            // Noop
        }
        else if (srcRGB == GL_SRC_ALPHA && dstRGB == GL_ONE && srcAlpha == GL_ZERO && dstAlpha == GL_ONE) {
            // Noop
        }
        else if (srcRGB == GL_SRC_ALPHA && dstRGB == GL_ONE_MINUS_SRC_ALPHA && srcAlpha == GL_ZERO && dstAlpha == GL_ONE) {
            // Noop
        }
        else if (srcRGB == GL_DST_COLOR && dstRGB == GL_ZERO && srcAlpha == GL_ZERO && dstAlpha == GL_ONE) {
            // Noop
        }
        else if (srcRGB == GL_DST_COLOR && dstRGB == GL_ZERO && srcAlpha == GL_ONE && dstAlpha == GL_ZERO) {
            // Noop
        }
        else if (srcRGB != srcAlpha || dstRGB != dstAlpha) {
            CONFIG::debug {
                if (log) log.send("[WARNING] glBlendFuncSeparate missing blend func: srcRGB = " + srcRGB + ", drtRGB = " +
                        dstRGB + ", srcA = " + srcAlpha + ", dstA = " + dstAlpha);
            }
        }

        if (this._contextEnableBlending && !this.disableBlending) {
            this.context.setBlendFactors(_contextSrcBlendFunc, _contextDstBlendFunc);
        }
    }

    // ======================================================================
    //  Functions
    // ----------------------------------------------------------------------

    protected function create2DTexture(width:int, height:int, level:int, data:ByteArray, dataOff:uint, dataLen:int = -1, format = "bgra", compressedUpload:Boolean = false):void {
        var instance:TextureInstance = this._activeTexture;
        if (!instance) {
            CONFIG::debug {
                if (log) log.send("[NOTE] No previously bound texture for glTexImage2D/glCompressedTexImage2D (2D)");
            }
            return;
        }

        CONFIG::debug {
            if (log2)
                log2.send("[NOTE] create 2D texture: WxH " + width + "x" + height + " l:" + level + " f:" + format +
                        " c:" + compressedUpload);
        }

        var texture:Texture = null;
        var rectTexture:RectangleTexture = null;
        if (!instance.texture) {
            var nonPowerOfTwo:Boolean = false;
            if (!compressedUpload && format == "bgra") {
                var logTwo:Number = 0.6931471805599453;
                var powT:Number = Math.log(width) / logTwo;
                if (powT - int(powT) > 0)
                    nonPowerOfTwo = true;
                if (!nonPowerOfTwo) {
                    powT = Math.log(height) / logTwo;
                    if (powT - int(powT) > 0)
                        nonPowerOfTwo = true;
                }
            }

            if (nonPowerOfTwo) {
                instance.texture = rectTexture = this.context.createRectangleTexture(width, height, format, dataOff == 0 ? true : false );
            } else {
                instance.texture = texture = this.context.createTexture(width, height, format, dataOff == 0 ? true : false );
            }

            this._textureSamplers[this._activeTextureUnit] = instance;
        }

        if (level >= instance.mipLevels) {
            instance.mipLevels = level + 1;
        }

        // FIXME (egeorgie) - we need a boolean param instead?
        if (dataOff > 0)
        {
            var bytes:ByteArray = null;
            // if (dataLen > -1) {
            // bytes = new ByteArray;
            // bytes.endian = Endian.LITTLE_ENDIAN;
            // bytes.writeBytes(data, dataOff, dataLen);
            // bytes.position = 0;
            // dataOff = 0;
            // } else {
            bytes = data;
            // }

            if (compressedUpload) {
                CONFIG::debug {
                    if (log) log.send("[DEBUG] texture.uploadCompressedTextureFromByteArray(data, dataOff(" + dataOff +
                            "), level(" + level + ") width: " + width + ", height: " + height);
                    if (log) log.send("[DEBUG] data[length: " + data.length + ", bytes: " + data.bytesAvailable + "]");
                }
                texture.uploadCompressedTextureFromByteArray(bytes, dataOff);
            }
            else {
                CONFIG::debug {
                    if (log) log.send("[DEBUG] texture.uploadFromByteArray(data, dataOff(" + dataOff + "), level(" +
                            level + ") width: " + width + ", height: " + height);
                    if (log) log.send("[DEBUG] data[length: " + data.length + ", bytes: " + data.bytesAvailable + "]");
                }
                if (texture)
                    texture.uploadFromByteArray(bytes, dataOff, level);
                else
                    rectTexture.uploadFromByteArray(bytes, dataOff);
            }
        }
    }

    protected function createCubeTexture(width:int, target:uint, level:int, data:ByteArray, dataOff:uint, dataLen:int = -1, format = "bgra", compressedUpload:Boolean = false):void {
        var instance:TextureInstance = this._activeTexture;
        if (instance) {
            if (!instance.cubeTexture) {
                instance.cubeTexture = this.context.createCubeTexture(width, format, false);
                this._textureSamplers[this._activeTextureUnit] = instance;
            }

            if (dataOff > 0) {
                var side:int = target - GL_TEXTURE_CUBE_MAP_POSITIVE_X;

                if (compressedUpload)
                    instance.cubeTexture.uploadCompressedTextureFromByteArray(data, dataOff);
                else
                    instance.cubeTexture.uploadFromByteArray(data, dataOff, side, level);
            }
        }
        else if (log) log.send("[NOTE] No previously bound texture for glCompressedTexImage2D (2D)");
    }

}
}

import GLS3D.GLAPI;

import flash.display3D.*;
import flash.display3D.textures.*;
import flash.utils.*;

class BufferInstance {
    public var id:uint;
    public var data:ByteArray;
    public var size:uint;
    public var type:uint;
    public var stride:uint;
    public var vertexBuffer:VertexBuffer3D;
    public var indexBuffer:IndexBuffer3D;
    public var uploaded:Boolean;
}

class TextureInstance {

    public var boundType:uint;
    public var texID:uint;

    private var _dirty:Boolean;
    private var _cacheKey:String;

    private var _texture:TextureBase;
    final public function get texture():TextureBase { return _texture; }
    final public function set texture(value:TextureBase):void {
        if (_texture == value) return;
        _texture = value;
        _dirty = true;
    }

    private var _cubeTexture:CubeTexture;
    final public function get cubeTexture():CubeTexture { return _cubeTexture; }
    final public function set cubeTexture(value:CubeTexture):void {
        if (_cubeTexture == value) return;
        _cubeTexture = value;
        _dirty = true;
    }

    private var _mipLevels:uint;
    final public function get mipLevels():uint { return _mipLevels; }
    final public function set mipLevels(value:uint):void {
        if (_mipLevels == value) return;
        _mipLevels = value;
        _dirty = true;
    }

    private var _params:TextureParams = new TextureParams();
    final public function get params():TextureParams { return _params; }
    final public function set params(value:TextureParams):void {
        if (value == _params) return;
        _params = value;
        _dirty = true;
    }

    private var _format:String = "bgra";
    final public function get format():String { return _format; }
    final public function set format(value:String):void {
        if (value == _format) return;
        _format = value;
        _dirty = true;
    }

    private var _compressed:Boolean;
    final public function get compressed():Boolean { return _compressed; }
    final public function set compressed(value:Boolean):void {
        if (value == _compressed) return;
        _compressed = value;
        _dirty = true;
    }

    final public function get key():String {
        if (!_cacheKey || _dirty) {
            _cacheKey = '';
            if (!_params)
                _cacheKey += '0,0,0,0,0,';
            else {
                _cacheKey += _params.GL_TEXTURE_WRAP_S;
                _cacheKey += ',';
                _cacheKey += _params.GL_TEXTURE_WRAP_T;
                _cacheKey += ',';
                _cacheKey += _params.GL_TEXTURE_MAG_FILTER;
                _cacheKey += ',';
                _cacheKey += _params.GL_TEXTURE_MIN_FILTER;
                _cacheKey += ',';
                _cacheKey += _params.GL_TEXTURE_MAX_ANISOTROPY_EXT;
                _cacheKey += ',';
            }
            _cacheKey += (_mipLevels > 1 ? '1' : '0');
        }
        _dirty = false;
        return _cacheKey;
    }

} // TextureInstance

class TextureParams {
    public var GL_TEXTURE_MAX_ANISOTROPY_EXT:Number = -1;
    public var GL_TEXTURE_MAG_FILTER:Number = GLAPI.GL_LINEAR;
    public var GL_TEXTURE_MIN_FILTER:Number = GLAPI.GL_NEAREST_MIPMAP_LINEAR;
    public var GL_TEXTURE_MIN_LOD:Number = -1000.0;
    public var GL_TEXTURE_MAX_LOD:Number = 1000.0;
    public var GL_TEXTURE_WRAP_S:uint = GLAPI.GL_REPEAT;
    public var GL_TEXTURE_WRAP_T:uint = GLAPI.GL_REPEAT;
    public var GL_TEXTURE_ENV_MODE:uint = GLAPI.GL_MODULATE;

}

class VertexBufferBuilder {
    public static const HAS_COLOR:uint = 0x00000001;
    public static const HAS_TEXTURE2D:uint = 0x00000002;
    public static const HAS_NORMAL:uint = 0x00000004;
    public static const TEX_GEN_S_SPHERE:uint = 0x00000008;
    public static const TEX_GEN_T_SPHERE:uint = 0x00000010;
}

class FixedFunctionProgramInstance {
    public var program:Program3D;
    public var vertexStreamUsageFlags:uint = 0;
    public var hasTexture:Boolean = false;
    public var key:String;
}

class FramebufferInstance {
    public var id:uint;
    public var depthBuffer:RenderbufferInstance;
    public var stencilBuffer:RenderbufferInstance;
    public var colorBuffers:Vector.<RenderbufferInstance>;
    public var texture:TextureInstance; // render target
} // class FramebufferInstance

class RenderbufferInstance {
    public var id:uint;
    public var slot:int;
    public var format:int;
    public var depth:Boolean;
    public var stencil:Boolean;
    public var color:Boolean;
    public var bufferTexture:Texture = null;
} // class RenderbufferInstance

class ShaderInstance {
    public var id:uint;
    public var type:uint;
    public var agalcode:ByteArray;
    public var agalasm:String;
    public var json:Object;
}

class ProgramInstance {
    public var id:uint;
    public var program:Program3D;
    public var vertexShader:ShaderInstance;
    public var fragmentShader:ShaderInstance;
    public var attribMap:Dictionary = new Dictionary();
    public var fragmentSamplerStates:Vector.<FragmentSamplerState> = new <FragmentSamplerState>[];
    public var uploaded:Boolean;
}

class FragmentSamplerState {
    public var compressed:Boolean;
    public var format:String;
    public var key:String;
    public var flags:Array;
}

class VariableHandle {
    public var id:uint;
    public var shader:ShaderInstance;
    public var number:uint;
    public var name:String;
}

/**
 *  Represents the vertices as defined between calls of glBeing() and glEnd().
 *  Holds and instance to the associated shader program.
 */
class VertexStream {
    public var vertexBuffer:VertexBuffer3D;
    public var indexBuffer:IndexBuffer3D;
    public var vertexFlags:uint;
    public var program:FixedFunctionProgramInstance;
    public var polygonOffset:Boolean = false;
}

/**
 *  Represents consequtive context state changes as defined between calls of glNewList() and glEndList().
 *  A single CommandList can have multiple context state changes.
 */
class ContextState {
    public var textureSamplers:Vector.<int>;// = new Vector.<uint>(8)
    public var material:Material;
}

/**
 *  Records of the OpenGL commands between calls of glNewList() and glEndList().
 */
[ExcludeClass]
class CommandList {
    // Used during building, move out?
    public var executeOnCompile:Boolean = false;
    public var activeState:ContextState = null;

    // Storage
    public var commands:Vector.<Object> = new Vector.<Object>();

    public function ensureActiveState():ContextState {
        if (!activeState) {
            activeState = new ContextState();
            activeState.textureSamplers = new Vector.<int>(8);
            for (var i:int = 0; i < 8; i++) {
                activeState.textureSamplers[i] = -1; // Set to 'undefined'
            }

            activeState.material = new Material(); // don't initialize, so we know what has changed.
        }
        return activeState;
    }
}

[ExcludeClass]
class Light {
    public static const LIGHT_TYPE_POINT:uint = 0;
    public static const LIGHT_TYPE_DIRECTIONAL:uint = 1;
    [Ignore]
    public static const LIGHT_TYPE_SPOT:uint = 2;		// Not supported

    public var position:Vector.<Number>;
    public var ambient:Vector.<Number>;
    public var diffuse:Vector.<Number>;
    public var specular:Vector.<Number>;
    public var type:uint;

    // FIXME (klin): No spotlight for now...neverball doesn't use it

    public function Light(init:Boolean = false, isLight0:Boolean = false) {
        if (init) {
            position = new <Number>[0, 0, 1, 0];
            ambient = new <Number>[0, 0, 0, 1];
            diffuse = (isLight0) ? new <Number>[1, 1, 1, 1] :
                    new <Number>[0, 0, 0, 1];
            specular = (isLight0) ? new <Number>[1, 1, 1, 1] :
                    new <Number>[0, 0, 0, 1];
            type = LIGHT_TYPE_POINT;
        }
    }

    public function createClone():Light {
        var clone:Light = new Light(false);
        clone.position = (position) ? position.concat() : null;
        clone.ambient = (ambient) ? ambient.concat() : null;
        clone.diffuse = (diffuse) ? diffuse.concat() : null;
        clone.specular = (specular) ? specular.concat() : null;
        clone.type = type;
        return clone;
    }
}

[ExcludeClass]
class Material {
    public var ambient:Vector.<Number>;
    public var diffuse:Vector.<Number>;
    public var specular:Vector.<Number>;
    public var shininess:Number;
    public var emission:Vector.<Number>;

    public function Material(init:Boolean = false) {
        // If init is true, we initialize to default values.
        if (init) {
            ambient = new <Number>[0.2, 0.2, 0.2, 1.0];
            diffuse = new <Number>[0.8, 0.8, 0.8, 1.0];
            specular = new <Number>[0.0, 0.0, 0.0, 1.0];
            shininess = 0.0;
            emission = new <Number>[0.0, 0.0, 0.0, 1.0];
        }
    }

    public function createClone():Material {
        var clone:Material = new Material(false);
        clone.ambient = (ambient) ? ambient.concat() : null;
        clone.diffuse = (diffuse) ? diffuse.concat() : null;
        clone.specular = (specular) ? specular.concat() : null;
        clone.shininess = shininess;
        clone.emission = (emission) ? emission.concat() : null;
        return clone;
    }
}

[ExcludeClass]
class LightingState {
    public var enableColorMaterial:Boolean; // GL_COLOR_MATERIAL enable bit
    public var enableLighting:Boolean; // GL_LIGHTING enable bit
    public var lightsEnabled:Vector.<Boolean>;
    public var lights:Vector.<Light>;
    public var contextMaterial:Material;
}

[ExcludeClass]
class BufferNode {
    public var buffer:VertexBuffer3D;
    public var prev:int;
    public var next:int;
    public var count:uint;
    public var hash:uint;
}

[ExcludeClass]
class VertexBufferPool {
    private var hashToIndex:Dictionary = new Dictionary();
    private var bufferToIndex:Dictionary = new Dictionary(true);
    private var buffers:Vector.<BufferNode> = new Vector.<BufferNode>();
    private var tail:int = -1;
    private var head:int = -1;
    private var prevFrame:int = -1; // index of MRU node previous frame
    private var prevPrevFrame:int = -1; // index of MRU node two frames ago

    public function acquire(hash:uint, count:uint, data:ByteArray, dataPtr:uint):VertexBuffer3D {
//        // Debug:
//        var h:uint = calcHash(count, data, dataPtr)
//        if (h != hash)
//            trace("Hashes don't match: " + hash + " " + h)
//        else
//            trace("Hashes match: " + hash)

//        if (!(hash in hashToIndex))
//            return null
        void(data);
        void(dataPtr);

        var index:int = this.hashToIndex[hash] as int;

        if (index || (index == 0 && hash in this.hashToIndex)) {

            //        var index:int = hashToIndex[hash]
            var node:BufferNode = this.buffers[index];
            if (node.count != count)
                throw("Collision in count " + node.count + " != " + count);

            //        // Debug:
            //        var src:ByteArray = node.src
            //        src.position = 0
            //        data.position = dataPtr
            //        for (var i:int = 0; i < src.length / 4; i++)
            //            if (src.readUnsignedInt() != data.readUnsignedInt())
            //            {
            //                trace("Collision in data at vertex " + (i / 12) + ", offset " + (i % 12))
            //                // print out the source & dst data
            //                {
            //                    src.position = 0
            //                    data.position = dataPtr
            //                    for (i = 0; i < src.length / 4; i++)
            //                    {
            //                        var value:Number = src.readFloat()
            //                        var value1:Number = data.readFloat()
            //                        if (value != value1)
            //                            trace("Difference: at position " + i + ": " + value + " != " + value1)
            //                    }
            //
            //                    // Calculate improved hash function:
            //                    src.position = 0
            //                    data.position = dataPtr
            //                    var hash1:uint = calcHash(count, src, 0)
            //                    var hash2:uint = calcHash(count, data, dataPtr)
            //                    trace("Computed Hashes are " + hash1 + " (stored data), " + hash2 + " (new data), stored hash is " + node.hash)
            //                    return node.buffer
            //                }
            //            }

            return node.buffer;
        }
        return null;
    }

    // Debug:
    [Ignore]
    static public function calcHash(count:uint, data:ByteArray, dataPtr:uint):uint {
        const offset_basis:uint = 2166136261;
        // 32 bit FNV_prime = 224 + 28 + 0x93 = 16777619

        const prime:uint = 16777619;
        var hash:uint = offset_basis;

        data.position = dataPtr;
        for (var i:int = 0; i < count * 12 * 4; i++) {
            var v:uint = data.readUnsignedByte();

            hash = hash ^ v;
            hash = hash * prime;
        }
        return hash;
    }

    public function allocateOrReuse(hash:uint, count:uint, data:ByteArray, dataPtr:uint, context:Context3D):VertexBuffer3D {
        var index:int = reuseBufferNode(count);
        var node:BufferNode;
        if (index != -1) {
            node = this.buffers[index];
            // Remove the old entry
            delete this.hashToIndex[node.hash];
        }
        else {
            node = new BufferNode();
            node.count = count;
            node.buffer = context.createVertexBuffer(count, 12);
            index = insertNode(node);
        }

//        // Debug:
//        node.src = new ByteArray()
//        node.src.endian = data.endian
//        data.position = dataPtr
//        var length:int = count * 12 * 4
//        node.src.length = length
//        node.src.position = 0
//        data.readBytes(node.src, 0, length)
//        trace("Allocating: passed on hash " + hash + ", computed hash " + calcHash(count, data, dataPtr) + ", computed on copy " + calcHash(count, node.src, 0))

        node.buffer.uploadFromByteArray(data, dataPtr, 0, count);
        this.bufferToIndex[node.buffer] = index;
        this.hashToIndex[hash] = index;
        node.hash = hash;
        return node.buffer;
    }

    private function reuseBufferNode(count:uint):int {
        if (prevPrevFrame == -1)
            return -1;

        // Iterate backwards, starting from the tail
        var current:int = this.tail;
        var node:BufferNode = null;
        while (current != -1) {
            node = this.buffers[current];

            // Make sure we don't reuse a buffer that's been used this or last frame
            if (node.next == this.prevPrevFrame)
                return -1;

            // Found a node with correct count
            if (node.count == count)
                return current;

            current = node.prev;
        }
        return -1;
    }

    private function insertNode(node:BufferNode):int {
        var index:int = this.buffers.length;
        this.buffers.push(node);
        if (this.head == -1) {
            this.tail = index;
        }
        else {
            var headNode:BufferNode = this.buffers[this.head];
            headNode.prev = index;
        }
        node.next = this.head;
        node.prev = -1;
        this.head = index;
        return index;
    }

    public function markInUse(buffer:VertexBuffer3D):void {
        if (!(buffer in this.bufferToIndex))
            return;

        var index:int = this.bufferToIndex[buffer];

        // Already at the head?
        if (this.head == index)
            return;

        var node:BufferNode = this.buffers[index];

        // Make sure we adjust the pointers for MRU last Frame and the frame before
        if (this.prevPrevFrame == index)
            this.prevPrevFrame = node.next;
        if (this.prevFrame == index)
            this.prevFrame = node.next;

        // Update the neighboring nodes
        var prevNode:BufferNode = node.prev != -1 ? this.buffers[node.prev] : null;
        var nextNode:BufferNode = node.next != -1 ? this.buffers[node.next] : null;
        if (prevNode)
            prevNode.next = node.next;
        if (nextNode)
            nextNode.prev = node.prev;

        // Update the tail
        if (this.tail == index)
            this.tail = node.prev;

        // Update the head
        var headNode:BufferNode = this.buffers[head];
        headNode.prev = index;

        // Make the node the head of the list
        node.next = this.head;
        node.prev = -1;
        this.head = index;
    }

    public function nextFrame():void {
        this.prevPrevFrame = this.prevFrame;
        this.prevFrame = this.head;

        // FIXME (egeorgie): cleanup for nodes at the tail if we're exceeding limit?

        //trace(print)
    }

    [Ignore]
    // For debugging:
    private function get print():String {
        var output:String = "";
        var current:int = this.head;
        while (current != -1) {
            // var n:String = current.toString();
            if (this.prevFrame == current || this.prevPrevFrame == current)
                output += " | " + current.toString();
            else
                output += " " + current.toString();

            var node:BufferNode = this.buffers[current];
            current = node.next;
        }
        if (this.prevFrame == -1)
            output += " |";
        if (this.prevPrevFrame == -1)
            output += " |";
        return output;
    }
} // class VertexBufferPool

// vi:ft=as3 ts=4 sw=4 expandtab tw=120
