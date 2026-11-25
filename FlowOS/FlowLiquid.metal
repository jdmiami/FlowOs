#include <metal_stdlib>
using namespace metal;

float smoothUnion(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b-a)/k, 0.0, 1.0);
    return mix(b,a,h) - k*h*(1.0-h);
}
float membrane(float2 p, float2 touch, float time, float energy, float merge) {
    float a = atan2(p.y,p.x);
    float deform = sin(a*3.0 + time*1.8)*0.045 + cos(a*5.0-time)*0.025;
    float2 shift = touch*0.18;
    float2 q = p-shift;
    float d = length(q) - (0.70 + deform + energy*0.035);
    float2 satellite = float2(0.78,0.08) + touch*0.43;
    float other = length(p-satellite) - (0.26*merge);
    return merge > 0.01 ? smoothUnion(d,other,0.24*merge+0.01) : d;
}
// Analytic liquid field, synthetic optical dispersion and surface normals.
// No full-screen render pass or texture allocations; operates only on the orb.
[[ stitchable ]] half4 flowMembrane(float2 position, half4 color, float2 size,
                                    float time, float2 touch, float energy, float merge,
                                    half4 primary, half4 secondary, half4 accent) {
    float2 p = (position-size*0.5)/max(min(size.x,size.y)*0.5,1.0);
    float d = membrane(p,touch,time,energy,merge);
    float alpha = 1.0-smoothstep(-0.009,0.009,d);
    if(alpha <= 0.0) return half4(0.0);
    float2 e = float2(0.006,0.0);
    float2 grad = float2(membrane(p+e,touch,time,energy,merge)-membrane(p-e,touch,time,energy,merge),
                        membrane(p+e.yx,touch,time,energy,merge)-membrane(p-e.yx,touch,time,energy,merge));
    float2 n = grad / max(length(grad),0.0001);
    float depth = clamp(-d/0.7,0.0,1.0);
    float3 normal = normalize(float3(n*(1.0-depth),sqrt(max(depth,0.001))));
    float3 light = normalize(float3(-0.55,-0.65,0.9));
    float rim = pow(1.0-clamp(normal.z,0.0,1.0),2.2);
    float shine = pow(max(dot(normal,light),0.0),16.0);
    float2 refracted = p + n*(0.13*rim);
    float wave = 0.5+0.5*sin(refracted.x*3.1+refracted.y*2.3+time*0.7);
    float3 tint = mix(float3(primary.rgb),float3(secondary.rgb),wave);
    tint = mix(tint,float3(accent.rgb),smoothstep(-0.1,0.8,refracted.y)*0.48);
    tint = mix(tint,float3(1.0),0.15+0.30*shine+0.27*rim);
    tint += float3(0.045,0.0,-0.035)*rim*sin(atan2(normal.y,normal.x));
    return half4(half3(clamp(tint,0.0,1.0)*alpha),half(alpha))*color.a;
}
