#include <cassert>
#include "video_core/renderer_vulkan/clear_rect.h"
int main() {
    using Vulkan::ViewportClearBounds;
    auto left = ViewportClearBounds(0,1566,1392,-1566,0,0,1392,1566,2784,1568);
    assert(left.x==0 && left.y==0 && left.width==1392 && left.height==1566);
    auto right = ViewportClearBounds(1391,1566,1393,-1566,1391,0,1393,1566,2784,1568);
    assert(right.x==1391 && right.width==1393 && right.height==1566);
    auto clipped = ViewportClearBounds(0,1566,2784,-1566,100,200,300,400,2784,1568);
    assert(clipped.x==100 && clipped.y==200 && clipped.width==300 && clipped.height==400);
    auto outside = ViewportClearBounds(-50,0,40,100,0,0,100,100,100,100);
    assert(outside.width==0 && outside.height==0);
    auto full = ViewportClearBounds(0,1568,2784,-1568,0,0,8192,8192,2784,1568);
    assert(full.width==2784 && full.height==1568);
}
