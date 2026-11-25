import Foundation
var checks=0
func check(_ ok: @autoclosure () -> Bool, _ title:String) { precondition(ok(),title); checks += 1; print("PASS: \(title)") }
for size in [256,512] {
    let m=BonsaiMath(size:size), g=size/16, zside=size/8
    check(m.tokens==g*g,"\(size): token count")
    check(m.imgIDs().count==g*g*4 && Array(m.imgIDs().suffix(4)) == [0,Float(g-1),Float(g-1),0],"\(size): position IDs")
    for steps in [2,4,8] {
        let s=m.sigmas(steps:steps)
        check(s.count==steps+1 && s.first==1 && s.last==0 && zip(s,s.dropFirst()).allSatisfy{$0.0>$0.1},"\(size): \(steps)-step descending sigma schedule")
    }
    let n=m.noise(seed:42)
    check(n.count==g*g*128 && n.allSatisfy{$0.isFinite},"\(size): finite seeded noise")
    check(n==m.noise(seed:42) && n != m.noise(seed:43),"\(size): reproducible and distinct seeds")
    let lat=(0..<m.tokens*128).map{Float($0)}
    let z=m.unpatchify(lat,scale:Array(repeating:2,count:128),shift:Array(repeating:1,count:128))
    check(z.count==32*zside*zside,"\(size): decoder latent shape")
    var correct=true
    for c in [0,15,31] { for h in [0,g-1] { for w in [0,g-1] { for i in 0...1 { for j in 0...1 {
        let at=c*zside*zside+(2*h+i)*zside+2*w+j
        let input=(h*g+w)*128+c*4+i*2+j
        if z[at] != lat[input]*2+1 {correct=false}
    }}}}}
    check(correct,"\(size): channel/patch mapping and affine")
}
check(BonsaiMath.txtIDs().count==1024 && Array(BonsaiMath.txtIDs().suffix(4)) == [0,0,0,255],"Text position IDs")
print("\(checks) Bonsai host math checks passed")
