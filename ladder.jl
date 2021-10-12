### A Pluto.jl notebook ###
# v0.16.0

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ 52769350-23dd-11ec-20ce-c5816b434427
begin
	using DataFrames
	using Parquet
	using Chain
	using PlutoUI
	using HypertextLiteral
	using Dates
	using TimeZones
end

# ╔═╡ 58888548-00ee-4236-a4b5-b77c55e77cb6
"""
TODOS
-Should have, at most, 4 decimal points - so there's a bug
-Think there's a bug when have buy/sell overlap
-Think about transactions/flag - do I care? Probably - so have transaction variabl
""";

# ╔═╡ 78bf79f6-00a9-4e49-bb9d-6990cae20863
md"""
**Symbol** $(@bind symbol TextField(default="SPY"))
"""

# ╔═╡ 4213820d-cef3-4dcf-af2f-3b5c259bfe01
@bind range  RangeSlider(0:1:6.5*60)

# ╔═╡ 72ea1523-1474-4b76-a6b3-35e170074909
@bind tick Clock()

# ╔═╡ 826dcf3b-b0ad-4fcf-abdd-c0ac2b260313
parquetdir="..\\parse_deep\\output\\";

# ╔═╡ 14a68dec-2080-46a1-bb61-79e8c65b9bad
parquetfiles = readdir(parquetdir);

# ╔═╡ 8128140c-2946-40f0-ba8f-d2921a662c42
begin
	df = DataFrame(read_parquet(parquetdir * parquetfiles[1]))
	for parquetfile in parquetfiles[2:end]
		append!(df, DataFrame(read_parquet(parquetdir * parquetfile)))
	end
end

# ╔═╡ c5a0a6f5-eef6-478c-a1f7-dd8269f12d8f
symbol_df = @chain df begin
	filter(:symbol => ==(symbol), _)
	select(:timestamp, :size, :price, :side)
	sort(:timestamp)
end;

# ╔═╡ d20b48ea-49f3-4383-8a28-5e67874659fc
symbol_matrix = Matrix(symbol_df);

# ╔═╡ 96c3410f-194a-4a18-85d0-f8f88bdbb4e4
begin
	# start with UTC
	epoch = round(symbol_matrix[1,1] * 10^-9)	
	opening_bell = Dates.unix2datetime(epoch)
 	opening_bell = ZonedDateTime(opening_bell, tz"UTC")
	
	# switch to America/New_York to handle DST
	opening_bell = astimezone(opening_bell, tz"America/New_York")
	
	opening_bell = ZonedDateTime(
		DateTime(
			Dates.year(opening_bell),
			Dates.month(opening_bell),
			Dates.day(opening_bell),
			9,
			30,
			0
		),
		tz"America/New_York"
	)

	# switch back to UTC to be able to use as cursor
	opening_bell = DateTime(opening_bell, UTC)
end;

# ╔═╡ 23e9fb5d-6ff2-434f-91e6-553e7fedbd57
function seek(symbol_matrix, datetime, cursor = 1)
	timestamp = Dates.datetime2unix(datetime) * 10^9

	while(symbol_matrix[cursor,1] < timestamp)
		cursor += 1
	end
	
	return cursor
end;

# ╔═╡ 56e87182-2744-4bf7-974e-19974cbab6ce
from = opening_bell + Dates.Minute(range[1]);

# ╔═╡ 59e11e13-aded-48e1-b6d5-42097270e827
from_display = astimezone(ZonedDateTime(from, tz"UTC"), tz"America/New_York");

# ╔═╡ 2e6c213b-5424-47fc-b1b7-7b91d9b6841f
from_cursor = seek(symbol_matrix, from);

# ╔═╡ c826b776-367a-4392-8908-5d16fc4b7b5b
to = opening_bell + Dates.Minute(last(range));

# ╔═╡ 7219d2eb-bac0-4033-97fa-b9efd34a9d67
to_display = astimezone(ZonedDateTime(to, tz"UTC"), tz"America/New_York");

# ╔═╡ 635b154d-422c-4eda-a243-b450606bed60
md"""
**Run from 
$(Dates.format(from_display, "mm-dd-yy I:MM")) 
to 
$(Dates.format(to_display, "I:MM")).**
"""

# ╔═╡ 92e4bafc-7369-4831-8260-88c261edc9ea
function state(symbol_matrix, from, to, state=Dict())	
	for n in from:to
		timestamp, size, price, side = symbol_matrix[n, :]

		if haskey(state, price) # price already present 
			if size == 0 # delete if size is zero
				delete!(state, price)  
			else # update with new size and/or side
				state[price] = (size, side)
			end
		else # not present
			state[price] = (size, side)
		end		
	end

	return state
end;

# ╔═╡ d2e9b60b-eadb-4158-9a87-40eff892ca92
initial_state = state(symbol_matrix, 1, from_cursor);

# ╔═╡ 4c7841be-ea4a-4b78-9ede-accfb286d850
tick; begin
	tick_cursor = seek(symbol_matrix, from + Dates.Second(tick), from_cursor)
	current_state = state(symbol_matrix, from_cursor, tick_cursor, initial_state)
	
	ladder = []
	for key in sort(collect(keys(current_state)))
		if current_state[key][2] == "buy"
			push!(ladder, (current_state[key][1], key, ""))	
		else
			push!(ladder, ("", key, current_state[key][1]))				
		end
	end
	
	trs = ""
	for (buy, price, sell) in ladder 
		trs *= "<tr><td>$(buy)</td><td>$(price)</td><td>$(sell)</td></tr>\n"
	end
	
	current_datetime = from_display + Dates.Second(tick)
	HTML(
		"""
		<center>
			<b>$(Dates.format(current_datetime, "mm-dd-yy I:MM:SS"))</b>
		</center>
		<table>
			<tr><th>buy</th><th>price</th><th>sell</th></tr>
			$(trs)
		</table>
		"""
	)	
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
Chain = "8be319e6-bccf-4806-a6f7-6fae938471bc"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
HypertextLiteral = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
Parquet = "626c502c-15b0-58ad-a749-f091afb673ae"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
TimeZones = "f269a46b-ccf7-5d73-abea-4c690281aa53"

[compat]
Chain = "~0.4.8"
DataFrames = "~1.2.2"
HypertextLiteral = "~0.9.1"
Parquet = "~0.8.3"
PlutoUI = "~0.7.14"
TimeZones = "~1.5.7"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[BinaryProvider]]
deps = ["Libdl", "Logging", "SHA"]
git-tree-sha1 = "ecdec412a9abc8db54c0efc5548c64dfce072058"
uuid = "b99e7846-7c00-51b0-8f62-c81ae34c0232"
version = "0.5.10"

[[CategoricalArrays]]
deps = ["DataAPI", "Future", "Missings", "Printf", "Requires", "Statistics", "Unicode"]
git-tree-sha1 = "fbc5c413a005abdeeb50ad0e54d85d000a1ca667"
uuid = "324d7699-5711-5eae-9e2f-1d82baa6b597"
version = "0.10.1"

[[Chain]]
git-tree-sha1 = "cac464e71767e8a04ceee82a889ca56502795705"
uuid = "8be319e6-bccf-4806-a6f7-6fae938471bc"
version = "0.4.8"

[[CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[CodecZstd]]
deps = ["TranscodingStreams", "Zstd_jll"]
git-tree-sha1 = "d19cd9ae79ef31774151637492291d75194fc5fa"
uuid = "6b39b394-51ab-5f42-8807-6242bab2b4c2"
version = "0.7.0"

[[Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "31d0151f5716b655421d9d75b7fa74cc4e744df2"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.39.0"

[[ContextVariablesX]]
deps = ["Compat", "Logging", "UUIDs"]
git-tree-sha1 = "8ccaa8c655bc1b83d2da4d569c9b28254ababd6e"
uuid = "6add18c4-b38d-439d-96f6-d6bc489c04c5"
version = "0.1.2"

[[Crayons]]
git-tree-sha1 = "3f71217b538d7aaee0b69ab47d9b7724ca8afa0d"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.0.4"

[[DataAPI]]
git-tree-sha1 = "cc70b17275652eb47bc9e5f81635981f13cea5c8"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.9.0"

[[DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Reexport", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "d785f42445b63fc86caa08bb9a9351008be9b765"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.2.2"

[[DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "7d9d316f04214f7efdbb6398d545446e246eff02"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.10"

[[DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[Decimals]]
git-tree-sha1 = "e98abef36d02a0ec385d68cd7dadbce9b28cbd88"
uuid = "abce61dc-4473-55a0-ba07-351d65e31d42"
version = "0.4.1"

[[DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[ExprTools]]
git-tree-sha1 = "b7e3d17636b348f005f11040025ae8c6f645fe92"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.6"

[[Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[HypertextLiteral]]
git-tree-sha1 = "f6532909bf3d40b308a0f360b6a0e626c0e263a8"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.1"

[[IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[InvertedIndices]]
git-tree-sha1 = "bee5f1ef5bf65df56bdd2e40447590b272a5471f"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.1.0"

[[IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "642a199af8b68253517b80bd3bfd17eb4e84df6e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.3.0"

[[JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "8076680b162ada2a031f707ac7b4953e30667a37"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.2"

[[LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[LinearAlgebra]]
deps = ["Libdl"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[LittleEndianBase128]]
deps = ["Test"]
git-tree-sha1 = "2cad132b52c86e0ccfc75116362ab57f0047893a"
uuid = "1724a1d5-ab78-548d-94b3-135c294f96cf"
version = "0.3.0"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[Mocking]]
deps = ["Compat", "ContextVariablesX", "ExprTools"]
git-tree-sha1 = "d5ca7901d59738132d6f9be9a18da50bc85c5115"
uuid = "78c3b35d-d492-501b-9361-3d52fe80e533"
version = "0.7.4"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[Parquet]]
deps = ["CategoricalArrays", "CodecZlib", "CodecZstd", "DataAPI", "Dates", "Decimals", "LittleEndianBase128", "Missings", "Mmap", "SentinelArrays", "Snappy", "Tables", "Thrift"]
git-tree-sha1 = "7e811ac653d0363ebf50cae76adc8f2e290eb2b6"
uuid = "626c502c-15b0-58ad-a749-f091afb673ae"
version = "0.8.3"

[[Parsers]]
deps = ["Dates"]
git-tree-sha1 = "a8709b968a1ea6abc2dc1967cb1db6ac9a00dfb6"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.0.5"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[PlutoUI]]
deps = ["Base64", "Dates", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "d1fb76655a95bf6ea4348d7197b22e889a4375f4"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.14"

[[PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a193d6ad9c45ada72c14b731a318bedd3c2f00cf"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.3.0"

[[Preferences]]
deps = ["TOML"]
git-tree-sha1 = "00cfd92944ca9c760982747e9a1d0d5d86ab1e5a"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.2.2"

[[PrettyTables]]
deps = ["Crayons", "Formatting", "Markdown", "Reexport", "Tables"]
git-tree-sha1 = "6330e0c350997f80ed18a9d8d9cb7c7ca4b3a880"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "1.2.0"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[RecipesBase]]
git-tree-sha1 = "44a75aa7a527910ee3d1751d1f0e4148698add9e"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.1.2"

[[Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "4036a3bd08ac7e968e27c203d45f5fff15020621"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.1.3"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "54f37736d8934a12a200edea2f9206b03bdf3159"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.7"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[Snappy]]
deps = ["BinaryProvider", "Libdl", "Random", "Test"]
git-tree-sha1 = "25620a91907972a05863941d6028791c2613888e"
uuid = "59d4ed8c-697a-5b28-a4c7-fe95c22820f9"
version = "0.3.0"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "TableTraits", "Test"]
git-tree-sha1 = "1162ce4a6c4b7e31e0e6b14486a6986951c73be9"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.5.2"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[Thrift]]
deps = ["Distributed", "Sockets", "ThriftJuliaCompiler_jll"]
git-tree-sha1 = "080fb72b35b43001dfdb769b1a21ca65cdd91ba5"
uuid = "8d9c9c80-f77e-5080-9541-c6f69d204e22"
version = "0.8.2"

[[ThriftJuliaCompiler_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "949a51ca85d31b063531eed49e38a6c9b9bae58b"
uuid = "815b9798-8dd0-5549-95cc-3cf7d01bce66"
version = "0.12.1+0"

[[TimeZones]]
deps = ["Dates", "Future", "LazyArtifacts", "Mocking", "Pkg", "Printf", "RecipesBase", "Serialization", "Unicode"]
git-tree-sha1 = "6c9040665b2da00d30143261aea22c7427aada1c"
uuid = "f269a46b-ccf7-5d73-abea-4c690281aa53"
version = "1.5.7"

[[TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "216b95ea110b5972db65aa90f88d8d89dcb8851c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.6"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "cc4bf3fdde8b7e3e9fa0351bdeedba1cf3b7f6e6"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.0+0"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
"""

# ╔═╡ Cell order:
# ╠═58888548-00ee-4236-a4b5-b77c55e77cb6
# ╟─78bf79f6-00a9-4e49-bb9d-6990cae20863
# ╟─635b154d-422c-4eda-a243-b450606bed60
# ╟─4213820d-cef3-4dcf-af2f-3b5c259bfe01
# ╟─72ea1523-1474-4b76-a6b3-35e170074909
# ╠═4c7841be-ea4a-4b78-9ede-accfb286d850
# ╠═52769350-23dd-11ec-20ce-c5816b434427
# ╠═826dcf3b-b0ad-4fcf-abdd-c0ac2b260313
# ╠═14a68dec-2080-46a1-bb61-79e8c65b9bad
# ╠═8128140c-2946-40f0-ba8f-d2921a662c42
# ╠═c5a0a6f5-eef6-478c-a1f7-dd8269f12d8f
# ╠═d20b48ea-49f3-4383-8a28-5e67874659fc
# ╠═96c3410f-194a-4a18-85d0-f8f88bdbb4e4
# ╠═23e9fb5d-6ff2-434f-91e6-553e7fedbd57
# ╠═56e87182-2744-4bf7-974e-19974cbab6ce
# ╠═59e11e13-aded-48e1-b6d5-42097270e827
# ╠═2e6c213b-5424-47fc-b1b7-7b91d9b6841f
# ╠═c826b776-367a-4392-8908-5d16fc4b7b5b
# ╠═7219d2eb-bac0-4033-97fa-b9efd34a9d67
# ╠═92e4bafc-7369-4831-8260-88c261edc9ea
# ╠═d2e9b60b-eadb-4158-9a87-40eff892ca92
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
