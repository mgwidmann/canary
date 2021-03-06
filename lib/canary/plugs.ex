defmodule Canary.Plugs do
  import Canada.Can, only: [can?: 3]
  import Ecto.Query
  import Keyword, only: [has_key?: 2]

  @doc """
  Load the resource given by conn.params["id"] and ecto model given by
  opts[:model] into conn.assigns.loaded_resource.

  If the resource cannot be fetched, conn.assigns.load_resource is set
  to nil.

  If the action is "index", all records from the specified model will be loaded.

  Currently, new and create actions are ignored, and conn.assigns.loaded_resource
  will be set to nil for these actions.

  """
  def load_resource(conn, opts) do
    conn
    |> action_valid?(opts)
    |> case do
      true  -> _load_resource(conn, opts)
      false -> conn
    end
  end

  defp _load_resource(conn, opts) do
    loaded_resource = case get_action(conn) do
      :index  ->
        fetch_all(conn, opts)
      :new    ->
        nil
      :create ->
        nil
      _       ->
        fetch_resource(conn, opts)
    end

    %{ conn | assigns: Map.put(conn.assigns, :loaded_resource, loaded_resource) }
  end

  @doc """
  Authorize the current user for the given resource.

  In order to use this function,
    1) conn.assigns.current_user must be an ecto struct representing the current user
    2) conn.private must be a map.

  If authorization succeeds, assign conn.assigns.authorized to true.
  If authorization fails, assign conn.assigns.authorized to false.

  For the "index", "new", and "create" actions, the resource in the Canada.Can implementation
  should be the module name of the model rather than a struct.

  For example:
    use         def can?(%User{}, :index, Post), do: true
    instead of  def can?(%User{}, :index, %Post{}), do: true
  """
  def authorize_resource(conn, opts) do
    conn
    |> action_valid?(opts)
    |> case do
      true  -> _authorize_resource(conn, opts)
      false -> conn
    end
  end

  defp _authorize_resource(conn, opts) do
    current_user = conn.assigns.current_user
    action = get_action(conn)

    resource = cond do
      action in [:index, :new, :create] ->
        opts[:model]
      true      ->
        fetch_resource(conn, opts)
    end

    case current_user |> can? action, resource do
      true  ->
        %{ conn | assigns: Map.put(conn.assigns, :authorized, true) }
      false ->
        %{ conn | assigns: Map.put(conn.assigns, :authorized, false) }
    end
  end

  @doc """
  Authorize the given resource and then load it if
  authorization succeeds.

  If the resource cannot be loaded or authorization
  fails, conn.assigns.loaded_resource is set to nil.

  The result of the authorization (true/false) is
  assigned to conn.assigns.authorized.

  Also, see the documentation for load_resource/2 and
  authorize_resource/2.
  """
  def load_and_authorize_resource(conn, opts) do
    conn
    |> action_valid?(opts)
    |> case do
      true  -> _load_and_authorize_resource(conn, opts)
      false -> conn
    end
  end

  defp _load_and_authorize_resource(conn, opts) do
    conn
    |> load_resource(opts)
    |> authorize_resource(opts)
    |> purge_resource_if_unauthorized(opts)
  end

  defp purge_resource_if_unauthorized(conn = %{assigns: %{authorized: true} }, _opts), do: conn
  defp purge_resource_if_unauthorized(conn = %{assigns: %{authorized: false} }, _opts) do
    %{ conn | assigns: Map.put(conn.assigns, :loaded_resource, nil) }
  end

  defp fetch_resource(conn = %{assigns: %{loaded_resource: resource}}, opts) when resource != nil do
    (resource.__struct__ == opts[:model])
    |> case do
      true  ->
        resource
      false ->
        Application.get_env(:canary, :repo).get(opts[:model], conn.params["id"])
    end
  end

  defp fetch_resource(conn, opts) do
    Application.get_env(:canary, :repo).get(opts[:model], conn.params["id"])
  end

  defp fetch_all(%{assigns: %{loaded_resource: resource}}, opts) do
    (resource.__struct__ == opts[:model])
    |> case do
      true  ->
        resource
      false ->
        from(m in opts[:model])
        |> select([m], m)
        |> Application.get_env(:canary, :repo).all
    end
  end

  defp fetch_all(_conn, opts) do
     from(m in opts[:model])
     |> select([m], m)
     |> Application.get_env(:canary, :repo).all
  end

  defp get_action(conn) do
    conn.assigns
    |> Map.fetch(:action)
    |> case do
      {:ok, action} -> action
      _             -> conn.private.phoenix_action
    end
  end

  defp action_exempt?(conn, opts) do
    action = get_action(conn)

    (is_list(opts[:except]) && action in opts[:except])
    |> case do
      true  -> true
      false -> action == opts[:except]
    end
  end

  defp action_included?(conn, opts) do
    action = get_action(conn)

    (is_list(opts[:only]) && action in opts[:only])
    |> case do
      true  -> true
      false -> action == opts[:only]
    end
  end

  defp action_valid?(conn, opts) do
    cond do
      has_key?(opts, :except) && has_key?(opts, :only) ->
        false
      has_key?(opts, :except) ->
        !action_exempt?(conn, opts)
      has_key?(opts, :only) ->
        action_included?(conn, opts)
      true ->
        true
    end
  end
end
