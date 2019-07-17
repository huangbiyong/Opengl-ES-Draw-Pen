
precision highp float;

uniform sampler2D texture;
varying lowp vec4 color;
//out vec4 fout_color;

void main()
{
    
    gl_FragColor = color;
}
