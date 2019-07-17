#import "PaintingView.h"
#import "shaderUtil.h"
#import "fileUtil.h"
#import "debug.h"



#define kBrushScale			2


// Shaders
enum {
    PROGRAM_POINT,
    NUM_PROGRAMS
};

enum {
	UNIFORM_MVP,
    UNIFORM_POINT_SIZE,
    UNIFORM_VERTEX_COLOR,
    UNIFORM_TEXTURE,
	NUM_UNIFORMS
};

enum {
	ATTRIB_VERTEX,
	NUM_ATTRIBS
};

typedef struct {
	char *vert, *frag;
	GLint uniform[NUM_UNIFORMS];
	GLuint id;
} programInfo_t;

programInfo_t program[NUM_PROGRAMS] = {
    { "point.vsh",   "point.fsh" },     // PROGRAM_POINT
};


// Texture
typedef struct {
    GLuint id;
    GLsizei width, height;
} textureInfo_t;



@interface PaintingView()
{
	// The pixel dimensions of the backbuffer
	GLint backingWidth;
	GLint backingHeight;
	
	EAGLContext *context;
	
	GLuint viewRenderbuffer, viewFramebuffer;
    GLuint depthRenderbuffer;
	
	textureInfo_t brushTexture;     // brush texture
    GLfloat brushColor[4];          // brush color
    
    // Shader objects
    GLuint vertexShader;
    GLuint fragmentShader;
    GLuint shaderProgram;
    
    // Buffer Objects
    GLuint vboId;
    
    BOOL initialized;
}

@end

@implementation PaintingView


+ (Class)layerClass {
	return [CAEAGLLayer class];
}


-(void)layoutSubviews {
    
    if (!initialized) {
        initialized = [self initGL];
    }
}

- (BOOL)initGL {
    
    // 1. 设置Layer
    [self setupEAGLLayer];
    
    // 2. 设置上下文
    [self setupContext];
    
    // 3. 设置帧缓存和渲染缓存
    [self setupFramebuffersAndRenderbuffer];
    
    // 4. 设置视口
    glViewport(0, 0, backingWidth, backingHeight);
    
    // 5. 设置数组数据缓存
    glGenBuffers(1, &vboId);
    
    // 6. 加载着色器
    [self setupShaders];
    

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    

    // 7. 设置投影视图矩阵
    [self setupMVPMatrix];
    
    // 8. 执行一次清除缓存操作
    [self erase];
    

    return YES;
}

- (void)setupEAGLLayer {
    
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    eaglLayer.opaque = YES;
    eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
    
    self.contentScaleFactor = [[UIScreen mainScreen] scale];
}

- (BOOL)setupContext {
    
    context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!context || ![EAGLContext setCurrentContext:context]) {
        return NO;
    }
    return YES;
}

- (BOOL)setupFramebuffersAndRenderbuffer {
    
    glGenFramebuffers(1, &viewFramebuffer);
    glGenRenderbuffers(1, &viewRenderbuffer);
    
    glBindFramebuffer(GL_FRAMEBUFFER, viewFramebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, viewRenderbuffer);
    
    [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(id<EAGLDrawable>)self.layer];
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, viewRenderbuffer);
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    
    
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        return NO;
    }
  
    return YES;
}


- (void)setupShaders {
    
	for (int i = 0; i < NUM_PROGRAMS; i++)
	{
		char *vsrc = readFile(pathForResource(program[i].vert));
		char *fsrc = readFile(pathForResource(program[i].frag));
		GLsizei attribCt = 0;
		GLchar *attribUsed[NUM_ATTRIBS];
		GLint attrib[NUM_ATTRIBS];
		GLchar *attribName[NUM_ATTRIBS] = {
			"inVertex",
		};
		const GLchar *uniformName[NUM_UNIFORMS] = {
			"MVP", "pointSize", "vertexColor", "texture",
		};
		
		// auto-assign known attribs
		for (int j = 0; j < NUM_ATTRIBS; j++)
		{
			if (strstr(vsrc, attribName[j]))
			{
				attrib[attribCt] = j;
				attribUsed[attribCt++] = attribName[j];
			}
		}
		
		glueCreateProgram(vsrc, fsrc,
                          attribCt, (const GLchar **)&attribUsed[0], attrib,
                          NUM_UNIFORMS, &uniformName[0], program[i].uniform,
                          &program[i].id);
		free(vsrc);
		free(fsrc);
        

        if (i == PROGRAM_POINT)
        {
            glUseProgram(program[PROGRAM_POINT].id);
            
            // GLKMatrix4MakeOrtho(float left, float right, float bottom, float top, float nearZ, float farZ)
            GLKMatrix4 projectionMatrix = GLKMatrix4MakeOrtho(0, backingWidth, 0, backingHeight, 0, 1);
            GLKMatrix4 modelViewMatrix = GLKMatrix4Identity; // this sample uses a constant identity modelView matrix
            GLKMatrix4 MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
            
            glUniformMatrix4fv(program[PROGRAM_POINT].uniform[UNIFORM_MVP], 1, GL_FALSE, MVPMatrix.m);
        
            // point size
            glUniform1f(program[PROGRAM_POINT].uniform[UNIFORM_POINT_SIZE], brushTexture.width / kBrushScale);
            
            // initialize brush color
            glUniform4fv(program[PROGRAM_POINT].uniform[UNIFORM_VERTEX_COLOR], 1, brushColor);
        }
	}
    
    glError();
}


- (void)setupMVPMatrix {

    GLKMatrix4 projectionMatrix = GLKMatrix4MakeOrtho(0, backingWidth, 0, backingHeight, 0, 1);
    GLKMatrix4 modelViewMatrix = GLKMatrix4Identity;
    GLKMatrix4 MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
    
    glUseProgram(program[PROGRAM_POINT].id);
    glUniformMatrix4fv(program[PROGRAM_POINT].uniform[UNIFORM_MVP], 1, GL_FALSE, MVPMatrix.m);
}



- (void)erase {
    
    [self clearPoint];
    
	[EAGLContext setCurrentContext:context];
	
	// 1. 清除缓存区
	glBindFramebuffer(GL_FRAMEBUFFER, viewFramebuffer);
	glClearColor(0.0, 0.0, 0.0, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);
	
	// 2. 显示渲染缓存区
	glBindRenderbuffer(GL_RENDERBUFFER, viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER];
}


- (void)renderLine {

    // 1. 将线条顶点数据从 CPU 复制到 GPU
    glBindBuffer(GL_ARRAY_BUFFER, vboId);
    glBufferData(GL_ARRAY_BUFFER, self.vertexIndex * sizeof(GLfloat), self.vertexBuffer, GL_DYNAMIC_DRAW);

    // 2. 设置顶点可用，和顶点 GPU 读取顶点方式
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);

    // 3. 使用Program
    glUseProgram(program[PROGRAM_POINT].id);

    // 4. 绘制线条
    [context presentRenderbuffer:GL_RENDERBUFFER];
    
    glLineWidth(7.0f);
    glDrawArrays(GL_LINE_STRIP, (int)self.vertexEnd/2, (int)((self.vertexIndex - self.vertexEnd)/2));

}


#pragma mark - 触摸处理
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    self.lineIndex = 0;
}


- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    
    self.lineIndex++;
    
	CGRect	 bounds = [self bounds];
	UITouch *touch  = [[event touchesForView:self] anyObject];

    self.location = [touch locationInView:self];
    self.location = CGPointMake(self.location.x * self.contentScaleFactor, (bounds.size.height - self.location.y) * self.contentScaleFactor);
    [self addPoint:self.location];
    
    [self renderLine];
}


- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    self.vertexEnd = self.vertexIndex;
}



- (void)addPoint:(CGPoint)point {
    
    if(self.vertexBuffer == NULL) {
        self.vertexBuffer = malloc(20 * sizeof(GLfloat));
        self.vertexIndex = 0;
        self.vertexCount = 20;
    }
    
    if (self.vertexIndex*2 >= self.vertexCount) {
        self.vertexCount += 20;
        self.vertexBuffer = realloc(self.vertexBuffer, self.vertexCount  * sizeof(GLfloat));
    }

    
//    if (self.lineIndex > 2) {
//
//        CGFloat distance = [self distance:self.previousLocation toPoint:point];
//        if (distance > 4 && self.vertexIndex >= 4) {
//
//            CGFloat x0 = (self.vertexBuffer[self.vertexIndex-2] + self.vertexBuffer[self.vertexIndex-4])/2.0;
//            CGFloat y0 = (self.vertexBuffer[self.vertexIndex-1] + self.vertexBuffer[self.vertexIndex-3])/2.0;
//
//            CGFloat x1 = self.vertexBuffer[self.vertexIndex-2];
//            CGFloat y1 = self.vertexBuffer[self.vertexIndex-1];
//
//            CGFloat x2 = point.x;
//            CGFloat y2 = point.y;
//
//            NSInteger index = 0;
//
//            for (CGFloat t = 1.0/distance; t <=1.0000; t += 1.0/distance) {
//
//                if (self.vertexIndex*2 >= self.vertexCount) {
//                    self.vertexCount += 20;
//                    self.vertexBuffer = realloc(self.vertexBuffer, self.vertexCount * sizeof(GLfloat));
//                }
//
//                //二次贝塞尔曲线
//                CGFloat t1 = powf((1.0f -t ), 2);
//                CGFloat t2 = powf(t, 2);
//                CGFloat t3 = 2.0f * t * (1.0f - t);
//
//                CGFloat x = t1 * x0 + t3 * x1 + t2*x2;
//                CGFloat y = t1 * y0 + t3 * y1 + t2*y2;
//
//                if (index == 0) {
//
//                    //self.vertexBuffer[self.vertexIndex-2] = (NSInteger)x;
//                    //self.vertexBuffer[self.vertexIndex-1] = (NSInteger)y;
//
//                }else {
//                    self.vertexBuffer[self.vertexIndex] = (NSInteger)x;
//                    self.vertexBuffer[self.vertexIndex+1] = (NSInteger)y;
//                    self.vertexIndex += 2;
//                }
//
//                index ++ ;
//
//            }
//
//        }
//        else if (self.vertexIndex == 4) {
//
//            CGFloat x0 = (self.vertexBuffer[self.vertexIndex-2] + self.vertexBuffer[self.vertexIndex-4])/2.0;
//            CGFloat y0 = (self.vertexBuffer[self.vertexIndex-1] + self.vertexBuffer[self.vertexIndex-3])/2.0;
//            self.vertexBuffer[self.vertexIndex] = (NSInteger)x0;
//            self.vertexBuffer[self.vertexIndex+1] = (NSInteger)y0;
//
//            self.vertexBuffer[self.vertexIndex] = (NSInteger)point.x;
//            self.vertexBuffer[self.vertexIndex+1] = (NSInteger)point.y;
//
//            self.vertexIndex += 4;
//        }
//        else {
//            self.vertexBuffer[self.vertexIndex] = (NSInteger)point.x;
//            self.vertexBuffer[self.vertexIndex+1] = (NSInteger)point.y;
//            self.vertexIndex += 2;
//        }
//    } else {

        self.vertexBuffer[self.vertexIndex] = point.x;
        self.vertexBuffer[self.vertexIndex+1] = point.y;
        self.vertexIndex += 2;
//    }

    
    


}

- (CGFloat)distance:(CGPoint)prePoint toPoint:(CGPoint)toPoint {
    return sqrt(powf((toPoint.x - prePoint.x), 2) + powf((toPoint.y - prePoint.y), 2));
}

- (void)clearPoint {
    self.vertexBuffer = NULL;
    self.vertexIndex = 0;
    self.vertexCount = 20;
    self.vertexEnd = 0;
}


- (void)setBrushColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue {

    brushColor[0] = 1;
    brushColor[1] = 0;
    brushColor[2] = 0;
    brushColor[3] = 0.1;
    
    if (initialized) {
        glUseProgram(program[PROGRAM_POINT].id);
        glUniform4fv(program[PROGRAM_POINT].uniform[UNIFORM_VERTEX_COLOR], 1, brushColor);
    }
}


- (BOOL)canBecomeFirstResponder {
    return YES;
}



- (void)dealloc
{
    // Destroy framebuffers and renderbuffers
    if (viewFramebuffer) {
        glDeleteFramebuffers(1, &viewFramebuffer);
        viewFramebuffer = 0;
    }
    if (viewRenderbuffer) {
        glDeleteRenderbuffers(1, &viewRenderbuffer);
        viewRenderbuffer = 0;
    }
    if (depthRenderbuffer)
    {
        glDeleteRenderbuffers(1, &depthRenderbuffer);
        depthRenderbuffer = 0;
    }
    // texture
    if (brushTexture.id) {
        glDeleteTextures(1, &brushTexture.id);
        brushTexture.id = 0;
    }
    // vbo
    if (vboId) {
        glDeleteBuffers(1, &vboId);
        vboId = 0;
    }
    
    // tear down context
    if ([EAGLContext currentContext] == context)
        [EAGLContext setCurrentContext:nil];
}

@end
