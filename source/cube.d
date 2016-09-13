struct Vertex {
    float posX, posY, posZ, posW; // Position data
    float r, g, b, a;             // Color

	this(float x, float y, float z
		   , float r, float g, float b)
	{
		posX=x;
		posY=y;
		posZ=z;
		posW=1.0f;

		this.r=r;
		this.g=g;
		this.b=b;
		this.a=1.0f;
	}
};

static const Vertex[] g_vbData = [
    Vertex(-1, -1, -1, 0, 0, 0),
    Vertex(1, -1, -1, 1, 0, 0),
    Vertex(-1, 1, -1, 0, 1, 0),
    Vertex(-1, 1, -1, 0, 1, 0),
    Vertex(1, -1, -1, 1, 0, 0),
    Vertex(1, 1, -1, 1, 1, 0),

    Vertex(-1, -1, 1, 0, 0, 1),
    Vertex(-1, 1, 1, 0, 1, 1),
    Vertex(1, -1, 1, 1, 0, 1),
    Vertex(1, -1, 1, 1, 0, 1),
    Vertex(-1, 1, 1, 0, 1, 1),
    Vertex(1, 1, 1, 1, 1, 1),

    Vertex(1, 1, 1, 1, 1, 1),
    Vertex(1, 1, -1, 1, 1, 0),
    Vertex(1, -1, 1, 1, 0, 1),
    Vertex(1, -1, 1, 1, 0, 1),
    Vertex(1, 1, -1, 1, 1, 0),
    Vertex(1, -1, -1, 1, 0, 0),

    Vertex(-1, 1, 1, 0, 1, 1),
    Vertex(-1, -1, 1, 0, 0, 1),
    Vertex(-1, 1, -1, 0, 1, 0),
    Vertex(-1, 1, -1, 0, 1, 0),
    Vertex(-1, -1, 1, 0, 0, 1),
    Vertex(-1, -1, -1, 0, 0, 0),

    Vertex(1, 1, 1, 1, 1, 1),
    Vertex(-1, 1, 1, 0, 1, 1),
    Vertex(1, 1, -1, 1, 1, 0),
    Vertex(1, 1, -1, 1, 1, 0),
    Vertex(-1, 1, 1, 0, 1, 1),
    Vertex(-1, 1, -1, 0, 1, 0),

    Vertex(1, -1, 1, 1, 0, 1),
    Vertex(1, -1, -1, 1, 0, 0),
    Vertex(-1, -1, 1, 0, 0, 1),
    Vertex(-1, -1, 1, 0, 0, 1),
    Vertex(1, -1, -1, 1, 0, 0),
    Vertex(-1, -1, -1, 0, 0, 0),
];

static const Vertex[] g_vb_solid_face_colors_Data = [
    //red face
    Vertex(-1,-1, 1, 1, 0, 0),
    Vertex(-1, 1, 1, 1, 0, 0),
    Vertex( 1,-1, 1, 1, 0, 0),
    Vertex( 1,-1, 1, 1, 0, 0),
    Vertex(-1, 1, 1, 1, 0, 0),
    Vertex( 1, 1, 1, 1, 0, 0),
    //green face
    Vertex(-1,-1,-1, 0, 1, 0),
    Vertex( 1,-1,-1, 0, 1, 0),
    Vertex(-1, 1,-1, 0, 1, 0),
    Vertex(-1, 1,-1, 0, 1, 0),
    Vertex( 1,-1,-1, 0, 1, 0),
    Vertex( 1, 1,-1, 0, 1, 0),
    //blue face
    Vertex(-1, 1, 1, 0, 0, 1),
    Vertex(-1,-1, 1, 0, 0, 1),
    Vertex(-1, 1,-1, 0, 0, 1),
    Vertex(-1, 1,-1, 0, 0, 1),
    Vertex(-1,-1, 1, 0, 0, 1),
    Vertex(-1,-1,-1, 0, 0, 1),
    //yellow face
    Vertex( 1, 1, 1, 1, 1, 0),
    Vertex( 1, 1,-1, 1, 1, 0),
    Vertex( 1,-1, 1, 1, 1, 0),
    Vertex( 1,-1, 1, 1, 1, 0),
    Vertex( 1, 1,-1, 1, 1, 0),
    Vertex( 1,-1,-1, 1, 1, 0),
    //magenta face
    Vertex( 1, 1, 1, 1, 0, 1),
    Vertex(-1, 1, 1, 1, 0, 1),
    Vertex( 1, 1,-1, 1, 0, 1),
    Vertex( 1, 1,-1, 1, 0, 1),
    Vertex(-1, 1, 1, 1, 0, 1),
    Vertex(-1, 1,-1, 1, 0, 1),
    //cyan face
    Vertex( 1,-1, 1, 0, 1, 1),
    Vertex( 1,-1,-1, 0, 1, 1),
    Vertex(-1,-1, 1, 0, 1, 1),
    Vertex(-1,-1, 1, 0, 1, 1),
    Vertex( 1,-1,-1, 0, 1, 1),
    Vertex(-1,-1,-1, 0, 1, 1),
];

struct VertexUV {
    float posX, posY, posZ, posW; // Position data
    float u, v;                   // texture u,v

	this(float x, float y, float z
		 , float u, float v)
	{
		posX=x;
		posY=y;
		posZ=z;
		this.u=u;
		this.v=v;
	}
};

static const VertexUV[] g_vb_texture_Data = [
    //left face
    VertexUV(-1,-1,-1, 1, 0),  // lft-top-front
    VertexUV(-1, 1, 1, 0, 1),  // lft-btm-back
    VertexUV(-1,-1, 1, 0, 0),  // lft-top-back
    VertexUV(-1, 1, 1, 0, 1),  // lft-btm-back
    VertexUV(-1,-1,-1, 1, 0),  // lft-top-front
    VertexUV(-1, 1,-1, 1, 1),  // lft-btm-front
    //front face
    VertexUV(-1,-1,-1, 0, 0),  // lft-top-front
    VertexUV( 1,-1,-1, 1, 0),  // rgt-top-front
    VertexUV( 1, 1,-1, 1, 1),  // rgt-btm-front
    VertexUV(-1,-1,-1, 0, 0),  // lft-top-front
    VertexUV( 1, 1,-1, 1, 1),  // rgt-btm-front
    VertexUV(-1, 1,-1, 0, 1),  // lft-btm-front
    //top face
    VertexUV(-1,-1,-1, 0, 1),  // lft-top-front
    VertexUV( 1,-1, 1, 1, 0),  // rgt-top-back
    VertexUV( 1,-1,-1, 1, 1),  // rgt-top-front
    VertexUV(-1,-1,-1, 0, 1),  // lft-top-front
    VertexUV(-1,-1, 1, 0, 0),  // lft-top-back
    VertexUV( 1,-1, 1, 1, 0),  // rgt-top-back
    //bottom face
    VertexUV(-1, 1,-1, 0, 0),  // lft-btm-front
    VertexUV( 1, 1, 1, 1, 1),  // rgt-btm-back
    VertexUV(-1, 1, 1, 0, 1),  // lft-btm-back
    VertexUV(-1, 1,-1, 0, 0),  // lft-btm-front
    VertexUV( 1, 1,-1, 1, 0),  // rgt-btm-front
    VertexUV( 1, 1, 1, 1, 1),  // rgt-btm-back
    //right face
    VertexUV( 1, 1,-1, 0, 1),  // rgt-btm-front
    VertexUV( 1,-1, 1, 1, 0),  // rgt-top-back
    VertexUV( 1, 1, 1, 1, 1),  // rgt-btm-back
    VertexUV( 1,-1, 1, 1, 0),  // rgt-top-back
    VertexUV( 1, 1,-1, 0, 1),  // rgt-btm-front
    VertexUV( 1,-1,-1, 0, 0),  // rgt-top-front
    //back face
    VertexUV(-1, 1, 1, 1, 1),  // lft-btm-back
    VertexUV( 1, 1, 1, 0, 1),  // rgt-btm-back
    VertexUV(-1,-1, 1, 1, 0),  // lft-top-back
    VertexUV(-1,-1, 1, 1, 0),  // lft-top-back
    VertexUV( 1, 1, 1, 0, 1),  // rgt-btm-back
    VertexUV( 1,-1, 1, 0, 0),  // rgt-top-back
];

