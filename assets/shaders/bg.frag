extern number time;
extern vec2 love_ScreenSize;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords)
{
    vec2 uv = screen_coords/love_ScreenSize.xy;
    vec3 col = vec3(0.5 + 0.5*sin(time + uv.xyx + vec3(0,2,4)));
    return vec4(col, 1.0);
}