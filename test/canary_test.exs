defmodule User do
  defstruct id: 1
end

defmodule Post do
  use Ecto.Model

  schema "posts" do
    field :user_id, :integer, default: 1
  end
end

defmodule Repo do
  def get(User, 1), do: %User{}
  def get(User, id), do: nil

  def get(Post, 1), do: %Post{id: 1}
  def get(Post, 2), do: %Post{id: 2, user_id: 2 }
  def get(Post, _), do: nil

  def all(_), do: [%Post{id: 1}, %Post{id: 2}]
end

defimpl Canada.Can, for: User do
  def can?(%User{id: user_id}, action, %Post{user_id: user_id})
  when action in [:show], do: true

  def can?(%User{}, :index, Post), do: true

  def can?(%User{}, action, Post)
    when action in [:new, :create], do: true

  def can?(%User{}, _, _), do: false
end

defimpl Canada.Can, for: Atom do
  def can?(nil, :create, Post), do: false
end


defmodule CanaryTest do
  use Canary

  import Plug.Adapters.Test.Conn, only: [conn: 4]

  use ExUnit.Case, async: true

  @moduletag timeout: 100000000

  Application.put_env :canary, :repo, Repo


  test "it loads the load resource correctly" do
    opts = [model: Post]

    # when the resource with the id can be fetched
    params = %{"id" => 1}
    conn = conn(%Plug.Conn{private: %{phoenix_action: :show}}, :get, "/posts/1", params)
    expected = %{conn | assigns: Map.put(conn.assigns, :loaded_resource, %Post{id: 1})}

    assert load_resource(conn, opts) == expected


    # when the resource with the id cannot be fetched
    params = %{"id" => 3}
    conn = conn(%Plug.Conn{private: %{phoenix_action: :show}}, :get, "/posts/3", params)
    expected = %{conn | assigns: Map.put(conn.assigns, :loaded_resource, nil)}

    assert load_resource(conn, opts) == expected


    # when the action is "index"
    params = %{}
    conn = conn(%Plug.Conn{private: %{phoenix_action: :index}}, :get, "/posts", params)
    expected = %{conn | assigns: Map.put(conn.assigns, :loaded_resource, [%Post{id: 1}, %Post{id: 2}])}

    assert load_resource(conn, opts) == expected


    # when the action is "new"
    params = %{}
    conn = conn(%Plug.Conn{private: %{phoenix_action: :new}}, :get, "/posts/new", params)
    expected = %{conn | assigns: Map.put(conn.assigns, :loaded_resource, nil)}

    assert load_resource(conn, opts) == expected


    # when the action is "create"
    params = %{}
    conn = conn(%Plug.Conn{private: %{phoenix_action: :create}}, :post, "/posts/create", params)
    expected = %{conn | assigns: Map.put(conn.assigns, :loaded_resource, nil)}

    assert load_resource(conn, opts) == expected
  end

  test "it authorizes the resource correctly" do
    opts = [model: Post]

    # when the action is "new"
    params = %{}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :new},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/new",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}

    assert authorize_resource(conn, opts) == expected


    # when the action is "create"
    params = %{}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :create},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/create",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}

    assert authorize_resource(conn, opts) == expected


    # when the action is "index"
    params = %{}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :index},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}

    assert authorize_resource(conn, opts) == expected


    # when the action is a phoenix action
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}

    assert authorize_resource(conn, opts) == expected


    # when the current user can access the given resource
    # and the action is specified in conn.assigns.action
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{},
        assigns: %{current_user: %User{id: 1}, action: :show}
      },
      :get,
      "/posts/1",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}

    assert authorize_resource(conn, opts) == expected


    # when both conn.assigns.action and conn.private.phoenix_action are defined
    # it uses conn.assigns.action for authorization
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}, action: :unauthorized}
      },
      :get,
      "/posts/1",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, false)}

    assert authorize_resource(conn, opts) == expected


    # when the current user cannot access the given resource
    params = %{"id" => 2}
    conn = conn(
      %Plug.Conn{
        private: %{},
        assigns: %{current_user: %User{id: 1}, action: :show}
      },
      :get,
      "/posts/2",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, false)}

    assert authorize_resource(conn, opts) == expected


    # when current_user is nil
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{},
        assigns: %{current_user: nil, action: :create}
      },
      :post,
      "/posts",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, false)}

    assert authorize_resource(conn, opts) == expected
  end

  test "it loads and authorizes the resource correctly" do
    opts = [model: Post]

    # when the current user can access the given resource
    # and the resource can be loaded
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}
    expected = %{expected | assigns: Map.put(expected.assigns, :loaded_resource, %Post{id: 1, user_id: 1})}

    assert load_and_authorize_resource(conn, opts) == expected


    # when the current user cannot access the given resource
    params = %{"id" => 2}
    conn = conn(
      %Plug.Conn{
        private: %{},
        assigns: %{current_user: %User{id: 1}, action: :show}
      },
      :get,
      "/posts/2",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, false)}
    expected = %{expected | assigns: Map.put(expected.assigns, :loaded_resource, nil)}

    assert load_and_authorize_resource(conn, opts) == expected


    # when the given resource cannot be loaded
    params = %{"id" => 3}
    conn = conn(
      %Plug.Conn{
        private: %{},
        assigns: %{current_user: %User{id: 1}, action: :show}
      },
      :get,
      "/posts/1",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, false)}
    expected = %{expected | assigns: Map.put(expected.assigns, :loaded_resource, nil)}

    assert load_and_authorize_resource(conn, opts) == expected
  end


  test "it only loads the resource when the action is in opts[:only]" do
    # when the action is in opts[:only]
    opts = [model: Post, only: :show]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :loaded_resource, %Post{id: 1})}

    assert load_resource(conn, opts) == expected


    # when the action is not opts[:only]
    opts = [model: Post, only: :other]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = conn

    assert load_resource(conn, opts) == expected
  end


  test "it only authorizes actions in opts[:only]" do
    # when the action is in opts[:only]
    opts = [model: Post, only: :show]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}
    assert authorize_resource(conn, opts) == expected


    # when the action is not opts[:only]
    opts = [model: Post, only: :other]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = conn

    assert authorize_resource(conn, opts) == expected
  end


  test "it only loads and authorizes the resource for actions in opts[:only]" do
    # when the action is in opts[:only]
    opts = [model: Post, only: :show]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}
    expected = %{conn | assigns: Map.put(expected.assigns, :loaded_resource, %Post{id: 1, user_id: 1})}

    assert load_and_authorize_resource(conn, opts) == expected


    # when the action is not opts[:only]
    opts = [model: Post, only: :other]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = conn

    assert load_and_authorize_resource(conn, opts) == expected
  end


  test "it skips the plug when both opts[:only] and opts[:except] are specified" do
    # when the plug is load_resource
    opts = [model: Post, only: :show, except: :index]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = conn

    assert load_resource(conn, opts) == expected


    # when the plug is authorize_resource
    opts = [model: Post, only: :show, except: :index]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = conn

    assert authorize_resource(conn, opts) == expected


    # when the plug is load_and_authorize_resource
    opts = [model: Post, only: :show, except: :index]
    params = %{"id" => 1}
    conn = conn(
    %Plug.Conn{
      private: %{phoenix_action: :show},
      assigns: %{current_user: %User{id: 1}}
    },
    :get,
    "/posts/1",
    params
    )
    expected = conn

    assert load_and_authorize_resource(conn, opts) == expected
  end

  test "it correctly skips authorization for exempt actions" do
    # when the action is exempt
    opts = [model: Post, except: :show]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = conn

    assert authorize_resource(conn, opts) == expected


    # when the action is not exempt
    opts = [model: Post]
    expected = %{conn | assigns: Map.put(expected.assigns, :authorized, true)}

    assert authorize_resource(conn, opts) == expected
  end


  test "it correctly skips loading resources for exempt actions" do
    # when the action is exempt
    opts = [model: Post, except: :show]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = conn
    assert load_resource(conn, opts) == expected


    # when the action is not exempt
    opts = [model: Post]
    expected = %{conn | assigns: Map.put(expected.assigns, :loaded_resource, %Post{id: 1, user_id: 1})}
    assert load_resource(conn, opts) == expected
  end


  test "it correctly skips load_and_authorize_resource for exempt actions" do
    # when the action is exempt
    opts = [model: Post, except: :show]
    params = %{"id" => 1}
    conn = conn(
      %Plug.Conn{
        private: %{phoenix_action: :show},
        assigns: %{current_user: %User{id: 1}}
      },
      :get,
      "/posts/1",
      params
    )
    expected = conn
    assert load_and_authorize_resource(conn, opts) == expected


    # when the action is not exempt
    opts = [model: Post]
    expected = %{conn | assigns: Map.put(conn.assigns, :authorized, true)}
    expected = %{expected | assigns: Map.put(expected.assigns, :loaded_resource, %Post{id: 1, user_id: 1})}
    assert load_and_authorize_resource(conn, opts) == expected
  end
end
